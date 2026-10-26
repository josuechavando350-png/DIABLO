// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {IVault4626} from "../../src/interfaces/IVault4626.sol";
import {VaultInvariantLib} from "../lib/VaultInvariantLib.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";

/// @notice SET DE INVARIANTES de la familia Vault ERC-4626. Genérico sobre IVault4626.
abstract contract VaultInvariants is StdInvariant, Test {
    IVault4626 internal vault;
    VaultHandler internal vaultHandler;

    /// V1 · El vault custodia al menos lo que contabiliza.
    function invariant_vault_accountingSolvent() public view {
        assertTrue(VaultInvariantLib.accountingSolvent(vault), "V1: contabilidad insolvente");
    }

    /// V2 · Ningún depósito recibe shares injustas (anti-inflación).
    function invariant_vault_depositFairness() public view {
        assertFalse(vaultHandler.brokeFairness(), "V2: un deposito recibio shares injustas");
    }

    /// V3 · La suma de lo redimible por todos nunca excede los activos.
    function invariant_vault_redemptionsSolvent() public view {
        assertTrue(
            VaultInvariantLib.redemptionsSolvent(vault, vaultHandler.getActors()),
            "V3: redenciones por encima de los activos"
        );
    }
}

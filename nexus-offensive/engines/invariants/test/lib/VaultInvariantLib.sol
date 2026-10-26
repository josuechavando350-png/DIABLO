// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVault4626} from "../../src/interfaces/IVault4626.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Predicados de invariante de la familia Vault ERC-4626.
library VaultInvariantLib {
    /// Holgura para absorber redondeo de 1 wei (no para ocultar robos).
    uint256 internal constant DUST = 1e9;

    /// V1 · Contabilidad solvente: el vault custodia al menos lo que contabiliza.
    function accountingSolvent(IVault4626 v) internal view returns (bool) {
        return IERC20(v.asset()).balanceOf(address(v)) >= v.totalAssets();
    }

    /// V3 · Redenciones solventes: la suma de lo redimible por todos nunca
    ///      excede los activos (el redondeo favorece al vault, no al usuario).
    function redemptionsSolvent(IVault4626 v, address[] memory users) internal view returns (bool) {
        uint256 sum;
        for (uint256 i; i < users.length; i++) {
            sum += v.convertToAssets(v.balanceOf(users[i]));
        }
        return sum <= v.totalAssets();
    }

    /// V2 · Justicia al depositante: las shares recibidas por `assetsIn` valen
    ///      ~`assetsIn` (defensa contra inflación de primer depositante).
    function depositWasFair(IVault4626 v, uint256 assetsIn, uint256 sharesOut)
        internal
        view
        returns (bool)
    {
        return v.convertToAssets(sharesOut) + DUST >= assetsIn;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {IVault4626} from "../interfaces/IVault4626.sol";

/// @title VulnerableVault4626 — vault ERC-4626 con el BUG de inflación
/// @notice `totalAssets` lee el balance real (cuenta donaciones directas), no
///         hay virtual shares / dead shares, y `deposit` NO exige `shares > 0`.
///         Un atacante deposita 1 wei, dona en grande para inflar el precio por
///         acción, y el siguiente depositante recibe 0 shares y pierde su
///         depósito. Educativo, no producción.
/// @dev Clase de bug: inflación de primer depositante + redondeo que perjudica
///      al depositante. Rompe la invariante "un depósito recibe shares justas".
contract VulnerableVault4626 is IVault4626 {
    IERC20 public immutable _assetToken;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(IERC20 a) {
        _assetToken = a;
    }

    function asset() external view returns (address) {
        return address(_assetToken);
    }

    // ❌ Cuenta donaciones directas: así se puede inflar el precio por acción.
    function totalAssets() public view returns (uint256) {
        return _assetToken.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets;
        return (assets * supply) / totalAssets(); // ❌ sin offset ni dead shares
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        return (shares * totalAssets()) / supply;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        // ❌ NO exige shares > 0: el depositante puede recibir 0 y perderlo todo.
        require(_assetToken.transferFrom(msg.sender, address(this), assets), "pull");
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        require(balanceOf[msg.sender] >= shares && shares > 0, "shares");
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        require(_assetToken.transfer(msg.sender, assets), "send");
    }
}

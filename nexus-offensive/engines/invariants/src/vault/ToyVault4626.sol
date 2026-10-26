// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {IVault4626} from "../interfaces/IVault4626.sol";

/// @title ToyVault4626 — vault ERC-4626 de juguete, SANO
/// @notice Usa CONTABILIDAD INTERNA de activos (`_accountedAssets`): ignora
///         transferencias directas (donaciones) al vault. Así el ataque de
///         inflación de primer depositante NO funciona — no se puede subir el
///         precio por acción donando. Además exige `shares > 0` al depositar.
///         Educativo, no producción.
contract ToyVault4626 is IVault4626 {
    IERC20 public immutable _assetToken;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    uint256 internal _accountedAssets; // solo lo depositado, no donaciones

    constructor(IERC20 a) {
        _assetToken = a;
    }

    function asset() external view returns (address) {
        return address(_assetToken);
    }

    function totalAssets() public view returns (uint256) {
        return _accountedAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets;
        return (assets * supply) / _accountedAssets;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 0;
        return (shares * _accountedAssets) / supply;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "zero shares"); // evita perder el depósito
        require(_assetToken.transferFrom(msg.sender, address(this), assets), "pull");
        _accountedAssets += assets;
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
    }

    function redeem(uint256 shares) external returns (uint256 assets) {
        require(balanceOf[msg.sender] >= shares && shares > 0, "shares");
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;
        _accountedAssets -= assets;
        require(_assetToken.transfer(msg.sender, assets), "send");
    }
}

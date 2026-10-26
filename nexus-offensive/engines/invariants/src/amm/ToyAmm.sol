// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";
import {IAmm} from "../interfaces/IAmm.sol";
import {Math} from "../lib/Math.sol";

/// @title ToyAmm — AMM de producto constante (tipo Uniswap V2), SANO
/// @notice Contrato de referencia de JUGUETE para la familia AMM. Educativo,
///         no es producción. Mantiene x·y=k con fee de 0.3% y contabilidad de
///         reservas explícita (reserva == balance real).
contract ToyAmm is IAmm {
    IERC20 public immutable t0;
    IERC20 public immutable t1;

    uint256 private _r0;
    uint256 private _r1;

    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityOf;

    uint256 public constant FEE_BPS = 30; // 0.3%
    uint256 private constant BPS = 10_000;

    constructor(IERC20 a, IERC20 b) {
        t0 = a;
        t1 = b;
    }

    function token0() external view returns (address) {
        return address(t0);
    }

    function token1() external view returns (address) {
        return address(t1);
    }

    function reserve0() public view returns (uint256) {
        return _r0;
    }

    function reserve1() public view returns (uint256) {
        return _r1;
    }

    /// @notice Aporta liquidez. El primer proveedor fija el precio; los demás
    ///         deben aportar en proporción a las reservas.
    function addLiquidity(uint256 amount0, uint256 amount1) external returns (uint256 shares) {
        if (totalLiquidity == 0) {
            shares = Math.sqrt(amount0 * amount1);
            require(shares > 0, "zero liquidity");
        } else {
            // Proporción exacta exigida (sin desbalancear el precio).
            require(amount1 == (amount0 * _r1) / _r0, "unbalanced");
            shares = (amount0 * totalLiquidity) / _r0;
            require(shares > 0, "zero shares");
        }
        require(t0.transferFrom(msg.sender, address(this), amount0), "t0");
        require(t1.transferFrom(msg.sender, address(this), amount1), "t1");
        _r0 += amount0;
        _r1 += amount1;
        totalLiquidity += shares;
        liquidityOf[msg.sender] += shares;
    }

    /// @notice Retira liquidez proporcional.
    function removeLiquidity(uint256 shares) external returns (uint256 amount0, uint256 amount1) {
        require(shares > 0 && liquidityOf[msg.sender] >= shares, "bad shares");
        amount0 = (shares * _r0) / totalLiquidity;
        amount1 = (shares * _r1) / totalLiquidity;
        liquidityOf[msg.sender] -= shares;
        totalLiquidity -= shares;
        _r0 -= amount0;
        _r1 -= amount1;
        require(t0.transfer(msg.sender, amount0), "t0");
        require(t1.transfer(msg.sender, amount1), "t1");
    }

    /// @notice Swap con fee 0.3% que PRESERVA el producto constante.
    function swap(uint256 amountIn, bool zeroForOne) external returns (uint256 amountOut) {
        require(amountIn > 0, "zero in");
        (uint256 rIn, uint256 rOut) = zeroForOne ? (_r0, _r1) : (_r1, _r0);
        require(rIn > 0 && rOut > 0, "no liquidity");

        uint256 amountInWithFee = (amountIn * (BPS - FEE_BPS)) / BPS;
        amountOut = (rOut * amountInWithFee) / (rIn + amountInWithFee);
        require(amountOut > 0 && amountOut < rOut, "bad out");

        IERC20 tokenIn = zeroForOne ? t0 : t1;
        IERC20 tokenOut = zeroForOne ? t1 : t0;
        require(tokenIn.transferFrom(msg.sender, address(this), amountIn), "in");
        require(tokenOut.transfer(msg.sender, amountOut), "out");

        if (zeroForOne) {
            _r0 += amountIn;
            _r1 -= amountOut;
        } else {
            _r1 += amountIn;
            _r0 -= amountOut;
        }
    }
}

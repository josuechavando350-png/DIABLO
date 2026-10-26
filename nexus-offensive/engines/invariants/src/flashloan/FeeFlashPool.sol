// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

interface IFeeFlashBorrower {
    function onFlashLoan(uint256 amount, uint256 fee) external;
}

/// @title ToyFeeFlashPool — flash loan con fee, SANO (autoriza al iniciador)
/// @notice Solo el propio receptor puede iniciar un préstamo que le cobra fee,
///         así que un tercero no puede vaciarlo con comisiones. Educativo.
contract ToyFeeFlashPool {
    IERC20 public token;
    uint256 public constant FEE = 1e18;

    constructor(IERC20 _token) {
        token = _token;
    }

    function flashLoan(address receiver, uint256 amount) external {
        require(msg.sender == receiver, "only receiver initiates"); // autorización
        require(token.transfer(receiver, amount), "t");
        IFeeFlashBorrower(receiver).onFlashLoan(amount, FEE);
        require(token.transferFrom(receiver, address(this), amount + FEE), "repay");
    }
}

/// @title VulnerableFeeFlashPool — cualquiera fuerza un préstamo con fee (naive)
/// @notice No verifica quién inicia: un tercero fuerza préstamos al receptor y
///         lo vacía vía comisiones. Rompe FL3. Educativo, no producción.
/// @dev Clase de bug: falta de autorización (movimiento de fondos sin consentimiento).
contract VulnerableFeeFlashPool {
    IERC20 public token;
    uint256 public constant FEE = 1e18;

    constructor(IERC20 _token) {
        token = _token;
    }

    function flashLoan(address receiver, uint256 amount) external {
        // ❌ BUG: no comprueba que el receptor haya pedido el préstamo.
        require(token.transfer(receiver, amount), "t");
        IFeeFlashBorrower(receiver).onFlashLoan(amount, FEE);
        require(token.transferFrom(receiver, address(this), amount + FEE), "repay");
    }
}

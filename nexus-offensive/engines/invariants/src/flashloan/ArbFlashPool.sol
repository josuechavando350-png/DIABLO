// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "../interfaces/IERC20.sol";

interface IArbBorrower {
    function onFlashLoan(uint256 amount) external;
}

/// @title ToyArbFlashPool — flash loan de tokens SANO (sin llamada arbitraria)
/// @notice El prestatario implementa un callback fijo y debe repagar. El pool
///         no ejecuta datos arbitrarios del atacante. Educativo.
contract ToyArbFlashPool {
    IERC20 public token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function flashLoan(uint256 amount, address borrower) external {
        uint256 before = token.balanceOf(address(this));
        require(token.transfer(borrower, amount), "t");
        IArbBorrower(borrower).onFlashLoan(amount);
        require(token.balanceOf(address(this)) >= before, "not repaid");
    }
}

/// @title VulnerableArbFlashPool — ejecuta una llamada ARBITRARIA (estilo truster)
/// @notice Deja que el prestatario pase target/data: se usa para que el pool se
///         auto-apruebe al atacante. Rompe FL2. Educativo, no producción.
/// @dev Clase de bug: llamada externa arbitraria con la autoridad del pool.
contract VulnerableArbFlashPool {
    IERC20 public token;

    constructor(IERC20 _token) {
        token = _token;
    }

    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data) external {
        uint256 before = token.balanceOf(address(this));
        require(token.transfer(borrower, amount), "t");
        (bool ok,) = target.call(data); // ❌ llamada arbitraria
        require(ok, "call failed");
        require(token.balanceOf(address(this)) >= before, "not repaid");
    }
}

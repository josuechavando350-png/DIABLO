// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title VulnerableVault — contrato de JUGUETE para el fork-validador
/// @notice INTENCIONALMENTE VULNERABLE a un drenaje por reentrancy.
///         Es material educativo para probar el pipeline de NEXUS Offensive
///         end-to-end: contrato -> invariante -> fork -> PoC -> veredicto.
///         NO lo despliegues. No es código de producción.
/// @dev El bug: `withdraw()` hace la transferencia externa ANTES de poner a
///      cero el saldo del llamante (viola checks-effects-interactions), así
///      que un receptor malicioso puede re-entrar y retirar en bucle hasta
///      vaciar la bóveda.
contract VulnerableVault {
    mapping(address => uint256) public balances;

    /// @notice Deposita ETH y acredita el saldo del remitente.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Retira TODO el saldo del remitente.
    /// @dev VULNERABLE: interacción (call) antes del efecto (poner saldo a 0).
    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "nothing to withdraw");

        // ❌ BUG: se envía el ETH antes de actualizar el estado.
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");

        // ❌ Demasiado tarde: la reentrancy ya drenó la bóveda usando este
        //    saldo que todavía no se había puesto a cero.
        balances[msg.sender] = 0;
    }

    /// @notice Activos realmente custodiados por la bóveda.
    function totalAssets() external view returns (uint256) {
        return address(this).balance;
    }
}

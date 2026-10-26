// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {ToyFlashLoanPool} from "../../src/flashloan/ToyFlashLoanPool.sol";
import {IFlashBorrower} from "../../src/interfaces/IFlashLoanPool.sol";

/// @notice Handler HONESTO para Flash Loan: depósitos/retiros válidos y flash
///         loans que se repagan de verdad. El propio handler es el prestatario.
contract FlashLoanHandler is CommonBase, StdCheats, StdUtils, IFlashBorrower {
    ToyFlashLoanPool public pool;
    address[] public actors;

    bool public brokeConservation; // ghost FL3

    constructor(ToyFlashLoanPool _pool) payable {
        pool = _pool;
        for (uint256 i = 0; i < 3; i++) {
            address a = address(uint160(0x6000 + i));
            actors.push(a);
            vm.deal(a, 1_000 ether);
        }
        // Siembra: el actor 0 deposita.
        vm.prank(actors[0]);
        pool.deposit{value: 100 ether}();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function deposit(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        amount = bound(amount, 1 ether, 500 ether);
        if (actor.balance < amount) return;
        vm.prank(actor);
        pool.deposit{value: amount}();
    }

    function withdraw(uint256 seed, uint256 amount) external {
        address actor = actors[seed % actors.length];
        uint256 bal = pool.depositOf(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(actor);
        pool.withdraw(amount);
    }

    /// @notice Flash loan HONESTO: el handler pide y repaga de inmediato.
    function flashLoanHonest(uint256 seed) external {
        uint256 held = address(pool).balance;
        if (held == 0) return;
        uint256 amount = bound(seed, 1, held);
        uint256 before = address(pool).balance;
        pool.flashLoan(amount);
        if (address(pool).balance < before) brokeConservation = true;
    }

    // Repago: devolver exactamente lo prestado.
    function onFlashLoan(uint256 amount) external payable override {
        (bool ok,) = address(pool).call{value: amount}("");
        require(ok, "repay");
    }

    receive() external payable {}
}

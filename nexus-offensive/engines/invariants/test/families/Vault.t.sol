// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VaultInvariants} from "../invariants/VaultInvariants.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";
import {IVault4626} from "../../src/interfaces/IVault4626.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ToyVault4626} from "../../src/vault/ToyVault4626.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Aplica el set de invariantes Vault al contrato SANO (ToyVault4626).
contract ToyVaultInvariantTest is VaultInvariants {
    function setUp() public {
        MockERC20 token = new MockERC20("DAI", "DAI");
        ToyVault4626 toy = new ToyVault4626(IERC20(address(token)));

        vaultHandler = new VaultHandler(toy, token);
        vault = IVault4626(address(toy));

        targetContract(address(vaultHandler));
    }
}

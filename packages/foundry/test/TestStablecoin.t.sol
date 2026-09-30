// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestStablecoin } from "../contracts/TestStablecoin.sol";
import { MockHts, HTS_ADDRESS } from "./mocks/MockHts.sol";

contract TestStablecoinTest is Test {
    TestStablecoin internal faucet;
    address internal user = makeAddr("user");

    function setUp() public {
        vm.warp(1_790_000_000);
        vm.etch(HTS_ADDRESS, address(new MockHts()).code);
        faucet = new TestStablecoin();
        faucet.initialize{ value: 20e8 }();
    }

    function test_claim_mintsToCaller() public {
        vm.prank(user);
        faucet.claim();
        assertEq(IERC20(faucet.token()).balanceOf(user), faucet.CLAIM_AMOUNT());
    }

    function test_claim_enforcesCooldown() public {
        vm.startPrank(user);
        faucet.claim();
        vm.expectRevert(
            abi.encodeWithSelector(TestStablecoin.ClaimTooSoon.selector, block.timestamp + faucet.CLAIM_COOLDOWN())
        );
        faucet.claim();

        vm.warp(block.timestamp + faucet.CLAIM_COOLDOWN());
        faucet.claim();
        vm.stopPrank();
        assertEq(IERC20(faucet.token()).balanceOf(user), 2 * faucet.CLAIM_AMOUNT());
    }

    function test_initialize_onlyOnce() public {
        vm.expectRevert(TestStablecoin.AlreadyInitialized.selector);
        faucet.initialize{ value: 20e8 }();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LendingMarket } from "../contracts/LendingMarket.sol";
import { OracleGuard } from "../contracts/oracle/OracleGuard.sol";
import { MarketFixture } from "./utils/MarketFixture.sol";
import { HTS_ADDRESS } from "./mocks/MockHts.sol";

contract LendingMarketTest is MarketFixture {
    uint256 internal constant COLLATERAL = 10_000 * ONE_HBAR; // $1,200 at $0.12
    uint256 internal constant MAX_BORROW = 780 * ONE_USDC; // 65% LTV

    function setUp() public override {
        super.setUp();
        _supply(lender, 50_000 * ONE_USDC);
    }

    /*//////////////////////////////////////////////////////////////
                                LENDERS
    //////////////////////////////////////////////////////////////*/

    function test_supply_mintsHtsSharesOneToOneOnEmptyMarket() public view {
        assertEq(shares.balanceOf(lender), 50_000 * ONE_USDC);
        assertEq(shares.totalSupply(), 50_000 * ONE_USDC);
        assertEq(usdc.balanceOf(address(market)), 50_000 * ONE_USDC);
    }

    function test_withdraw_burnsSharesAndReturnsAssetsWithInterest() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);
        vm.warp(block.timestamp + 365 days);
        _setAll(HBAR_PRICE);

        vm.startPrank(borrower);
        usdc.approve(address(market), type(uint256).max);
        vm.stopPrank();
        _fund(borrower, 100 * ONE_USDC);
        vm.prank(borrower);
        market.repay(borrower, type(uint256).max);

        uint256 held = shares.balanceOf(lender);
        vm.startPrank(lender);
        shares.approve(address(market), held);
        uint256 assets = market.withdraw(held);
        vm.stopPrank();

        assertGt(assets, 50_000 * ONE_USDC, "lender earned interest");
        assertEq(shares.totalSupply(), 0);
        assertEq(usdc.balanceOf(lender), 50_000 * ONE_USDC + assets);
    }

    function test_withdraw_revertsWhenCashIsLent() public {
        vm.deal(borrower, 1_000_000 * ONE_HBAR);
        _depositAndBorrow(borrower, 1_000_000 * ONE_HBAR, 40_000 * ONE_USDC);

        vm.startPrank(lender);
        shares.approve(address(market), 50_000 * ONE_USDC);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.InsufficientLiquidity.selector, 10_000 * ONE_USDC));
        market.withdraw(50_000 * ONE_USDC);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               BORROWERS
    //////////////////////////////////////////////////////////////*/

    function test_borrow_upToLtv() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);
        assertEq(usdc.balanceOf(borrower), MAX_BORROW);
        assertEq(market.debtOf(borrower), MAX_BORROW);
    }

    function test_borrow_revertsAboveLtv() public {
        vm.startPrank(borrower);
        market.depositCollateral{ value: COLLATERAL }();
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Undercollateralized.selector, MAX_BORROW + 1, MAX_BORROW));
        market.borrow(MAX_BORROW + 1);
        vm.stopPrank();
    }

    function test_withdrawCollateral_revertsIfItBreaksLtv() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW / 2);

        vm.startPrank(borrower);
        vm.expectRevert();
        market.withdrawCollateral(COLLATERAL * 6 / 10);
        market.withdrawCollateral(COLLATERAL * 4 / 10);
        vm.stopPrank();

        assertEq(borrower.balance, 100_000 * ONE_HBAR - COLLATERAL * 6 / 10);
    }

    function test_interest_accruesToBorrowers() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);
        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();

        uint256 debt = market.debtOf(borrower);
        // Utilization ~1.6%: ~2% base + ~0.3% slope. Allow for per-accrual rounding.
        assertApproxEqRel(debt, MAX_BORROW * 10_232 / 10_000, 0.001e18);
        assertEq(market.totalBorrows(), debt);
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    function test_liquidate_afterGradualPriceDrop() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);

        // Two steps below the guard's 20% per-step change limit: 0.12 -> 0.105 -> 0.095.
        _setAll(0.105e18);
        guard.poke();
        _setAll(0.095e18);

        uint256 repayAmount = MAX_BORROW / 2;
        vm.startPrank(liquidator);
        usdc.approve(address(market), repayAmount);
        uint256 seized = market.liquidate(borrower, repayAmount);
        vm.stopPrank();

        // 390 USDC / $0.095 * 1.05 bonus
        assertEq(seized, uint256(390 * ONE_USDC) * 1e20 / 0.095e18 * 10_500 / 10_000);
        assertEq(liquidator.balance, seized);
        assertEq(market.debtOf(borrower), MAX_BORROW - repayAmount);
    }

    function test_liquidate_revertsOnHealthyPosition() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);
        vm.prank(liquidator);
        vm.expectRevert(LendingMarket.PositionHealthy.selector);
        market.liquidate(borrower, 1);
    }

    function test_liquidate_revertsAboveCloseFactor() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW);
        _setAll(0.105e18);
        guard.poke();
        _setAll(0.095e18);

        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.RepayTooLarge.selector, MAX_BORROW / 2));
        market.liquidate(borrower, MAX_BORROW / 2 + 1);
    }

    /*//////////////////////////////////////////////////////////////
                         FAIL-CLOSED BEHAVIOUR
    //////////////////////////////////////////////////////////////*/

    function test_trippedBreaker_blocksPriceDependentActions() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW / 2);
        chainlink.setReverts(true);
        pyth.setReverts(true);

        bytes memory tripped =
            abi.encodeWithSelector(OracleGuard.BreakerTripped.selector, OracleGuard.TripReason.NoQuorum);

        vm.startPrank(borrower);
        vm.expectRevert(tripped);
        market.borrow(1);
        vm.expectRevert(tripped);
        market.withdrawCollateral(1);
        vm.stopPrank();

        vm.prank(liquidator);
        vm.expectRevert(tripped);
        market.liquidate(borrower, 1);
    }

    function test_trippedBreaker_leavesRiskReducingActionsOpen() public {
        _depositAndBorrow(borrower, COLLATERAL, MAX_BORROW / 2);
        chainlink.setReverts(true);
        pyth.setReverts(true);
        guard.poke();
        assertTrue(guard.isTripped());

        vm.startPrank(borrower);
        market.depositCollateral{ value: ONE_HBAR }();
        usdc.approve(address(market), 100 * ONE_USDC);
        market.repay(borrower, 100 * ONE_USDC);
        vm.stopPrank();

        _supply(lender, 1_000 * ONE_USDC);

        assertEq(market.debtOf(borrower), MAX_BORROW / 2 - 100 * ONE_USDC);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function test_initialize_keepsRenewalReserveAndRefundsRest() public {
        uint256 htsBefore = HTS_ADDRESS.balance;
        LendingMarket fresh = _market(guard);

        assertEq(address(fresh).balance, fresh.RENEWAL_RESERVE(), "reserve held back");
        assertEq(HTS_ADDRESS.balance - htsBefore, HTS_FEE - fresh.RENEWAL_RESERVE(), "rest paid to HTS");
    }

    function test_initialize_revertsWithoutFeeAboveReserve() public {
        LendingMarket fresh = new LendingMarket(address(usdc), 6, guard, _risk());
        uint256 reserve = fresh.RENEWAL_RESERVE();
        vm.expectRevert(LendingMarket.InvalidParams.selector);
        fresh.initialize{ value: reserve }("gUSDC", "gUSDC");
    }

    function test_initialize_onlyOnce() public {
        vm.expectRevert(LendingMarket.AlreadyInitialized.selector);
        market.initialize{ value: HTS_FEE }("Again", "AGN");
    }

    function test_constructor_rejectsBonusThatWouldCreateBadDebt() public {
        vm.expectRevert(LendingMarket.InvalidParams.selector);
        new LendingMarket(
            address(usdc),
            6,
            guard,
            LendingMarket.RiskParams({
                ltvBps: 8000,
                liquidationThresholdBps: 9500,
                liquidationBonusBps: 1000,
                closeFactorBps: 5000,
                baseRatePerSecond: 0,
                slopePerSecond: 0
            })
        );
    }
}

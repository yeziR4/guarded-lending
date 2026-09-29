// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LendingMarket } from "../contracts/LendingMarket.sol";
import { OracleGuard } from "../contracts/oracle/OracleGuard.sol";
import { IPriceSource } from "../contracts/oracle/IPriceSource.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MarketFixture } from "./utils/MarketFixture.sol";

/// @notice The July 2026 Bonzo Lend exploit (a forged Supra price ~10^12 too high) against the same market
///         code, wired to a single feed and then through the guard. Background: docs/oracle-guard.md.
contract BonzoReplayTest is MarketFixture {
    uint256 internal constant POOL = 100_000 * ONE_USDC;
    uint256 internal constant DUST_COLLATERAL = 250 * ONE_HBAR; // ~$30
    uint256 internal constant FORGED_MULTIPLIER = 1e12;

    address internal attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();
        vm.deal(attacker, DUST_COLLATERAL);
    }

    function test_singleFeedMarket_isDrainedByOneForgedPrice() public {
        OracleGuard singleFeed = _singleFeedOracle();
        market = _market(singleFeed);
        shares = IERC20(market.shareToken());
        _supply(lender, POOL);
        singleFeed.poke(); // market has been live at the honest price

        supra.set(HBAR_PRICE * FORGED_MULTIPLIER);
        _attack(POOL);

        assertEq(usdc.balanceOf(attacker), POOL, "attacker walked away with the whole pool");
        assertEq(usdc.balanceOf(address(market)), 0, "lenders left holding bad debt");
    }

    function test_guardedMarket_ignoresForgedFeedAndKeepsPricingHonestly() public {
        _supply(lender, POOL);
        supra.set(HBAR_PRICE * FORGED_MULTIPLIER);

        vm.startPrank(attacker);
        market.depositCollateral{ value: DUST_COLLATERAL }();
        IHRC719(address(usdc)).associate();
        // Priced at the honest median, $30 of HBAR supports ~$19.50 of debt.
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Undercollateralized.selector, POOL, 19_500_000));
        market.borrow(POOL);
        vm.stopPrank();

        (OracleGuard.Reading[] memory readings,,) = guard.inspect();
        assertEq(uint256(readings[1].status), uint256(OracleGuard.Status.OutOfBounds), "Supra excluded");
        assertEq(usdc.balanceOf(address(market)), POOL);
    }

    /// A subtler forgery that stays inside the absolute bounds is caught by the consensus check.
    function test_guardedMarket_rejectsPlausibleForgeryAsOutlier() public {
        _supply(lender, POOL);
        supra.set(HBAR_PRICE * 10);

        vm.startPrank(attacker);
        market.depositCollateral{ value: DUST_COLLATERAL }();
        vm.expectRevert(
            abi.encodeWithSelector(LendingMarket.Undercollateralized.selector, 1_000 * ONE_USDC, 19_500_000)
        );
        market.borrow(1_000 * ONE_USDC);
        vm.stopPrank();

        (OracleGuard.Reading[] memory readings,,) = guard.inspect();
        assertEq(uint256(readings[1].status), uint256(OracleGuard.Status.Outlier));
    }

    /// With two of three sources forged the guard cannot tell which side is honest, so it halts.
    function test_guardedMarket_failsClosedWhenMajorityCompromised() public {
        _supply(lender, POOL);
        supra.set(HBAR_PRICE * 10);
        pyth.set(HBAR_PRICE * 20);

        vm.startPrank(attacker);
        market.depositCollateral{ value: DUST_COLLATERAL }();
        vm.expectRevert(abi.encodeWithSelector(OracleGuard.BreakerTripped.selector, OracleGuard.TripReason.NoQuorum));
        market.borrow(1_000 * ONE_USDC);
        vm.stopPrank();

        guard.poke();
        assertTrue(guard.isTripped(), "anyone (or the Guardian) can persist the trip");
    }

    function _attack(uint256 amount) internal {
        vm.startPrank(attacker);
        market.depositCollateral{ value: DUST_COLLATERAL }();
        IHRC719(address(usdc)).associate();
        market.borrow(amount);
        vm.stopPrank();
    }

    /// Bonzo-style wiring: one feed, quorum of one, no bounds or change limit worth the name.
    function _singleFeedOracle() internal returns (OracleGuard) {
        IPriceSource[] memory sources = new IPriceSource[](1);
        sources[0] = supra;
        uint256[] memory ages = new uint256[](1);
        ages[0] = 1 hours;
        return new OracleGuard(
            sources,
            ages,
            OracleGuard.Params({
                quorum: 1,
                maxDeviationBps: 10_000,
                maxChangeBps: type(uint128).max,
                cooldown: 0,
                maxPriceAge: 10 minutes,
                minPriceE18: 1,
                maxPriceE18: type(uint128).max
            })
        );
    }
}

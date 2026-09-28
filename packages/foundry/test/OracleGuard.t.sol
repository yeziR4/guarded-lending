// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { OracleGuard } from "../contracts/oracle/OracleGuard.sol";
import { IPriceSource } from "../contracts/oracle/IPriceSource.sol";
import { MockPriceSource } from "./mocks/MockPriceSource.sol";

contract OracleGuardTest is Test {
    uint256 internal constant PRICE = 0.12e18;
    uint256 internal constant MAX_AGE = 1 hours;
    uint256 internal constant COOLDOWN = 30 minutes;

    MockPriceSource internal chainlink;
    MockPriceSource internal supra;
    MockPriceSource internal pyth;
    OracleGuard internal guard;

    function setUp() public {
        vm.warp(1_790_000_000);
        chainlink = new MockPriceSource("Chainlink", PRICE);
        supra = new MockPriceSource("Supra", PRICE);
        pyth = new MockPriceSource("Pyth", PRICE);
        guard = _guard(2);
    }

    function _guard(uint256 quorum) internal returns (OracleGuard) {
        IPriceSource[] memory sources = new IPriceSource[](3);
        sources[0] = chainlink;
        sources[1] = supra;
        sources[2] = pyth;
        uint256[] memory ages = new uint256[](3);
        ages[0] = MAX_AGE;
        ages[1] = MAX_AGE;
        ages[2] = MAX_AGE;
        return new OracleGuard(sources, ages, _params(quorum));
    }

    function _params(uint256 quorum) internal pure returns (OracleGuard.Params memory) {
        return OracleGuard.Params({
            quorum: quorum,
            maxDeviationBps: 500,
            maxChangeBps: 2000,
            cooldown: COOLDOWN,
            maxPriceAge: 10 minutes,
            minPriceE18: 0.001e18,
            maxPriceE18: 100e18
        });
    }

    /*//////////////////////////////////////////////////////////////
                              HAPPY PATH
    //////////////////////////////////////////////////////////////*/

    function test_poke_acceptsMedianWhenAllSourcesAgree() public {
        chainlink.set(0.118e18);
        supra.set(0.114e18);
        pyth.set(0.12e18);

        assertTrue(guard.poke());
        assertEq(guard.price(), 0.118e18);
        assertFalse(guard.isTripped());
    }

    function test_poke_evenValidCountUsesMeanOfMiddlePair() public {
        pyth.setReverts(true);
        chainlink.set(0.118e18);
        supra.set(0.114e18);

        assertTrue(guard.poke());
        assertEq(guard.price(), 0.116e18);
    }

    /*//////////////////////////////////////////////////////////////
                          SOURCE CLASSIFICATION
    //////////////////////////////////////////////////////////////*/

    function test_inspect_classifiesEachFailureMode() public {
        chainlink.setReverts(true);
        supra.setUpdatedAt(block.timestamp - MAX_AGE - 1);
        pyth.set(1_000e18);

        (OracleGuard.Reading[] memory readings, uint256 median, uint256 agreeing) = guard.inspect();

        assertEq(uint256(readings[0].status), uint256(OracleGuard.Status.Reverted));
        assertEq(uint256(readings[1].status), uint256(OracleGuard.Status.Stale));
        assertEq(uint256(readings[2].status), uint256(OracleGuard.Status.OutOfBounds));
        assertEq(median, 0);
        assertEq(agreeing, 0);
    }

    function test_inspect_flagsOutlierButKeepsQuorum() public {
        pyth.set(0.2e18);

        (OracleGuard.Reading[] memory readings, uint256 median, uint256 agreeing) = guard.inspect();

        assertEq(uint256(readings[2].status), uint256(OracleGuard.Status.Outlier));
        assertEq(median, PRICE);
        assertEq(agreeing, 2);
    }

    function test_inspect_futureTimestampIsNotStale() public {
        chainlink.setUpdatedAt(block.timestamp + 5);
        (OracleGuard.Reading[] memory readings,,) = guard.inspect();
        assertEq(uint256(readings[0].status), uint256(OracleGuard.Status.Ok));
    }

    /*//////////////////////////////////////////////////////////////
                             CIRCUIT BREAKER
    //////////////////////////////////////////////////////////////*/

    function test_poke_tripsWhenQuorumLost() public {
        chainlink.setReverts(true);
        pyth.setReverts(true);

        vm.expectEmit(address(guard));
        emit OracleGuard.Tripped(OracleGuard.TripReason.NoQuorum, PRICE);
        assertFalse(guard.poke());

        vm.expectRevert(abi.encodeWithSelector(OracleGuard.BreakerTripped.selector, OracleGuard.TripReason.NoQuorum));
        guard.price();
    }

    function test_poke_tripsWhenTwoSourcesDisagree() public {
        pyth.setReverts(true);
        supra.set(0.2e18);

        assertFalse(guard.poke());
        assertEq(uint256(guard.tripReason()), uint256(OracleGuard.TripReason.NoQuorum));
    }

    function test_poke_tripsOnExcessiveChange() public {
        guard.poke();
        chainlink.set(0.06e18);
        supra.set(0.06e18);
        pyth.set(0.06e18);

        assertFalse(guard.poke());
        assertEq(uint256(guard.tripReason()), uint256(OracleGuard.TripReason.ExcessiveChange));
        assertEq(guard.lastPrice(), PRICE);
    }

    function test_poke_resetsAfterFullHealthyCooldownAndReanchors() public {
        guard.poke();
        chainlink.set(0.06e18);
        supra.set(0.06e18);
        pyth.set(0.06e18);
        guard.poke();

        vm.warp(block.timestamp + COOLDOWN - 1);
        _refreshAll();
        assertFalse(guard.poke());

        vm.warp(block.timestamp + 1);
        _refreshAll();
        vm.expectEmit(address(guard));
        emit OracleGuard.Reset(0.06e18);
        assertTrue(guard.poke());
        assertEq(guard.price(), 0.06e18);
    }

    function test_poke_unhealthyCheckWhileTrippedRestartsCooldown() public {
        chainlink.setReverts(true);
        pyth.setReverts(true);
        guard.poke();

        vm.warp(block.timestamp + COOLDOWN - 1);
        supra.set(PRICE);
        guard.poke();
        uint256 extendedFrom = guard.trippedAt();
        assertEq(extendedFrom, block.timestamp);

        chainlink.setReverts(false);
        pyth.setReverts(false);
        vm.warp(block.timestamp + 10);
        _refreshAll();
        assertFalse(guard.poke(), "cooldown restarted by the unhealthy check");

        vm.warp(extendedFrom + COOLDOWN);
        _refreshAll();
        assertTrue(guard.poke());
    }

    function test_price_revertsWhenLastAcceptedPriceIsStale() public {
        guard.poke();
        vm.warp(block.timestamp + 10 minutes + 1);
        vm.expectRevert(abi.encodeWithSelector(OracleGuard.PriceStale.selector, block.timestamp - 10 minutes - 1));
        guard.price();
    }

    function test_price_revertsBeforeFirstPoke() public {
        vm.expectRevert(abi.encodeWithSelector(OracleGuard.PriceStale.selector, 0));
        guard.price();
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_constructor_requiresStrictMajorityQuorum() public {
        vm.expectRevert(OracleGuard.InvalidParams.selector);
        _guard(1);
        vm.expectRevert(OracleGuard.InvalidParams.selector);
        _guard(4);
    }

    function test_constructor_rejectsMismatchedAges() public {
        IPriceSource[] memory sources = new IPriceSource[](1);
        sources[0] = chainlink;
        vm.expectRevert(OracleGuard.InvalidSources.selector);
        new OracleGuard(sources, new uint256[](2), _params(1));
    }

    function test_constructor_rejectsInvertedBounds() public {
        IPriceSource[] memory sources = new IPriceSource[](1);
        sources[0] = chainlink;
        uint256[] memory ages = new uint256[](1);
        ages[0] = MAX_AGE;
        OracleGuard.Params memory params = _params(1);
        params.minPriceE18 = params.maxPriceE18;
        vm.expectRevert(OracleGuard.InvalidParams.selector);
        new OracleGuard(sources, ages, params);
    }

    /*//////////////////////////////////////////////////////////////
                                  FUZZ
    //////////////////////////////////////////////////////////////*/

    /// A single source can never move the accepted price, however far it is pushed.
    function testFuzz_singleCompromisedSourceCannotMovePrice(uint256 forged, uint8 which) public {
        forged = bound(forged, 1, type(uint128).max);
        MockPriceSource[3] memory all = [chainlink, supra, pyth];
        all[which % 3].set(forged);

        guard.poke();
        assertEq(guard.price(), PRICE);
    }

    function _refreshAll() internal {
        chainlink.set(chainlink.priceE18());
        supra.set(supra.priceE18());
        pyth.set(pyth.priceE18());
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Guardian } from "../contracts/Guardian.sol";
import { MarketFixture } from "./utils/MarketFixture.sol";
import { MockScheduleService } from "./mocks/MockScheduleService.sol";

contract GuardianTest is MarketFixture {
    address internal constant HSS = address(0x16b);
    uint256 internal constant INTERVAL = 5 minutes;
    uint256 internal constant GAS_LIMIT = 400_000;

    Guardian internal guardian;
    MockScheduleService internal hss;

    function setUp() public override {
        super.setUp();
        vm.etch(HSS, address(new MockScheduleService()).code);
        hss = MockScheduleService(HSS);
        hss.setHasCapacity(true);
        hss.setResponseCode(22);
        guardian = new Guardian(guard, market, INTERVAL, GAS_LIMIT);
    }

    function test_start_booksFirstTick() public {
        guardian.start{ value: ONE_HBAR }();

        assertEq(hss.scheduled(), 1);
        assertEq(hss.lastTo(), address(guardian));
        assertEq(hss.lastExpiry(), block.timestamp + INTERVAL);
        assertEq(hss.lastGasLimit(), GAS_LIMIT);
        assertEq(hss.lastCallData(), abi.encodeCall(Guardian.tick, ()));
        assertEq(guardian.nextRunAt(), block.timestamp + INTERVAL);
        assertEq(address(guardian).balance, ONE_HBAR);
    }

    function test_start_revertsWhileLoopIsLive() public {
        guardian.start();
        vm.expectRevert(abi.encodeWithSelector(Guardian.AlreadyRunning.selector, block.timestamp + INTERVAL));
        guardian.start();
    }

    function test_tick_whenDue_pokesGuardAndReschedules() public {
        guardian.start();
        vm.warp(block.timestamp + INTERVAL);
        _setAll(HBAR_PRICE);

        guardian.tick();

        assertEq(guardian.runs(), 1);
        assertEq(hss.scheduled(), 2);
        assertEq(guardian.nextRunAt(), block.timestamp + INTERVAL);
        assertEq(guard.lastPriceAt(), block.timestamp);
        assertEq(market.lastAccrual(), block.timestamp);
    }

    function test_tick_beforeDue_doesNotForkTheSchedule() public {
        guardian.start();
        vm.warp(block.timestamp + INTERVAL - guardian.BLOCK_TIME_TOLERANCE() - 1);

        guardian.tick();

        assertEq(guardian.runs(), 1);
        assertEq(hss.scheduled(), 1, "early manual tick must not book a second chain");
    }

    /// Regression for the live testnet run: the scheduled call executed at its booked second, but inside
    /// a record block whose `block.timestamp` was earlier, so the loop did not reschedule.
    function test_tick_scheduledExecutionSeesEarlierBlockTime_stillReschedules() public {
        guardian.start();
        vm.warp(block.timestamp + INTERVAL - 2);
        _setAll(HBAR_PRICE);

        guardian.tick();

        assertEq(hss.scheduled(), 2);
        assertEq(guardian.nextRunAt(), block.timestamp + INTERVAL);
    }

    function test_tick_afterEarlyManualTick_scheduledRunDoesNotDoubleBook() public {
        guardian.start();
        uint256 firstRunAt = guardian.nextRunAt();

        vm.warp(firstRunAt - 5);
        guardian.tick(); // manual, inside the tolerance: books the next run
        vm.warp(firstRunAt);
        guardian.tick(); // the original HSS execution arrives

        assertEq(guardian.runs(), 2);
        assertEq(hss.scheduled(), 2, "exactly one live schedule chain");
    }

    function test_tick_recordsTripWithoutReverting() public {
        guardian.start();
        chainlink.setReverts(true);
        pyth.setReverts(true);
        vm.warp(block.timestamp + INTERVAL);

        vm.expectEmit(address(guardian));
        emit Guardian.Ticked(1, false);
        guardian.tick();

        assertTrue(guard.isTripped());
        assertEq(hss.scheduled(), 2, "loop keeps running while tripped");
    }

    function test_scheduleFailure_stopsLoopAndAllowsRestart() public {
        guardian.start();
        hss.setResponseCode(-1);
        vm.warp(block.timestamp + INTERVAL);

        vm.expectEmit(address(guardian));
        emit Guardian.ScheduleFailed(-1);
        guardian.tick();
        assertEq(guardian.nextRunAt(), 0);

        hss.setResponseCode(22);
        guardian.start();
        assertEq(hss.scheduled(), 2);
    }

    function test_noCapacity_stopsLoop() public {
        hss.setHasCapacity(false);
        guardian.start();
        assertEq(guardian.nextRunAt(), 0);
        assertEq(hss.scheduled(), 0);
    }
}

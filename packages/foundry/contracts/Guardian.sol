// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { OracleGuard } from "./oracle/OracleGuard.sol";
import { LendingMarket } from "./LendingMarket.sol";
import { IHederaScheduleService } from "./interfaces/IHederaScheduleService.sol";
import { HederaResponseCodes } from "hedera-forking/HederaResponseCodes.sol";

/// @title Guardian
/// @notice Keeps the oracle check and interest accrual running without an off-chain keeper. Each
///         `tick()` pokes the guard, accrues interest, and books the next tick with the Hedera Schedule
///         Service (HIP-1215), so the chain of checks lives entirely on the network.
/// @dev The schedule is created with a direct CALL to the HSS system contract. Scheduling from a
///      DELEGATECALL frame is avoided on purpose (see hiero-consensus-node#27263).
///      The contract pays for its own scheduled executions, so keep it funded with HBAR.
contract Guardian {
    IHederaScheduleService private constant HSS = IHederaScheduleService(address(0x16b));
    int64 private constant HSS_SUCCESS = int64(HederaResponseCodes.SUCCESS);
    /// @dev Hedera's `block.timestamp` is the start of the ~2 s record block, so a schedule executing at
    ///      its booked second can observe a slightly earlier time. Observed on testnet: booked for
    ///      1790605316, executed at consensus 1790605316.07 inside a block that began a second earlier.
    uint256 public constant BLOCK_TIME_TOLERANCE = 10;
    /// @dev Gas kept back from the HSS call so a failed booking can still be recorded.
    uint256 private constant BOOKKEEPING_GAS = 30_000;
    /// @notice `ScheduleFailed` reasons that are not HSS response codes.
    int64 public constant NO_CAPACITY = -1;
    int64 public constant SCHEDULE_CALL_REVERTED = -2;

    error InvalidParams();
    error AlreadyRunning(uint256 nextRunAt);

    event Ticked(uint256 indexed run, bool healthy);
    event Scheduled(address schedule, uint256 runAt);
    event ScheduleFailed(int64 responseCode);

    OracleGuard public immutable GUARD;
    LendingMarket public immutable MARKET;
    uint256 public immutable INTERVAL;
    uint256 public immutable GAS_LIMIT;

    uint256 public runs;
    uint256 public nextRunAt;
    address public nextSchedule;

    constructor(OracleGuard guard, LendingMarket market, uint256 interval, uint256 gasLimit) {
        if (address(guard) == address(0) || address(market) == address(0) || interval == 0 || gasLimit == 0) {
            revert InvalidParams();
        }
        GUARD = guard;
        MARKET = market;
        INTERVAL = interval;
        GAS_LIMIT = gasLimit;
    }

    /// @notice Starts (or restarts, after the chain was broken) the scheduled loop. `msg.value` funds it.
    function start() external payable {
        if (nextRunAt != 0 && !_isDue()) revert AlreadyRunning(nextRunAt);
        _scheduleNext();
    }

    /// @notice Runs one check. Anyone may call it; only the first call once the run is due books the
    ///         following run, so extra calls never fork the schedule into parallel chains.
    function tick() external {
        bool healthy = GUARD.poke();
        MARKET.accrueInterest();
        emit Ticked(++runs, healthy);

        if (nextRunAt != 0 && _isDue()) _scheduleNext();
    }

    function _isDue() private view returns (bool) {
        return block.timestamp + BLOCK_TIME_TOLERANCE >= nextRunAt;
    }

    /// @dev Books the next tick. Any failure leaves the loop stopped (`nextRunAt == 0`) so `start()` can
    ///      restart it, and never reverts: the tick's oracle check must persist even if booking fails.
    function _scheduleNext() private {
        uint256 runAt = block.timestamp + INTERVAL;

        if (!HSS.hasScheduleCapacity(runAt, GAS_LIMIT)) {
            _stop(NO_CAPACITY);
            return;
        }

        // Booking a schedule costs ~1.4M gas on Hedera (the schedule fee is charged as gas), so a GAS_LIMIT
        // that is too small makes this call run out of gas. Keep enough back to record the failure.
        try HSS.scheduleCall{ gas: gasleft() - BOOKKEEPING_GAS }(
            address(this), runAt, GAS_LIMIT, 0, abi.encodeCall(this.tick, ())
        ) returns (
            int64 rc, address schedule
        ) {
            if (rc != HSS_SUCCESS || schedule == address(0)) {
                _stop(rc);
                return;
            }
            nextRunAt = runAt;
            nextSchedule = schedule;
            emit Scheduled(schedule, runAt);
        } catch {
            _stop(SCHEDULE_CALL_REVERTED);
        }
    }

    function _stop(int64 reason) private {
        nextRunAt = 0;
        emit ScheduleFailed(reason);
    }

    receive() external payable { }
}

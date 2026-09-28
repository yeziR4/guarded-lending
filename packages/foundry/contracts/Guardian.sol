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

    function _scheduleNext() private {
        uint256 runAt = block.timestamp + INTERVAL;
        nextRunAt = runAt;

        if (!HSS.hasScheduleCapacity(runAt, GAS_LIMIT)) {
            nextRunAt = 0;
            emit ScheduleFailed(-1);
            return;
        }

        (int64 rc, address schedule) =
            HSS.scheduleCall(address(this), runAt, GAS_LIMIT, 0, abi.encodeCall(this.tick, ()));
        if (rc != HSS_SUCCESS || schedule == address(0)) {
            // Leave the loop stopped so `start()` can restart it.
            nextRunAt = 0;
            emit ScheduleFailed(rc);
            return;
        }

        nextSchedule = schedule;
        emit Scheduled(schedule, runAt);
    }

    receive() external payable { }
}

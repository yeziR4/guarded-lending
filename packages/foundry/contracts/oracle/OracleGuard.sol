// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceSource } from "./IPriceSource.sol";

/// @title OracleGuard
/// @notice Median of independent price sources, accepted only when a quorum agrees and the move is within
///         limits; otherwise a breaker trips and `price()` reverts until the sources have been healthy
///         for a full cooldown. No admin key. Rules: docs/oracle-guard.md.
contract OracleGuard {
    uint256 private constant BPS = 10_000;
    uint256 public constant MAX_SOURCES = 5;

    enum Status {
        Ok,
        Reverted,
        Stale,
        OutOfBounds,
        Outlier
    }

    enum TripReason {
        None,
        NoQuorum,
        ExcessiveChange
    }

    struct Reading {
        uint256 priceE18;
        uint256 updatedAt;
        Status status;
    }

    struct Params {
        uint256 quorum;
        uint256 maxDeviationBps;
        uint256 maxChangeBps;
        uint256 cooldown;
        uint256 maxPriceAge;
        uint256 minPriceE18;
        uint256 maxPriceE18;
    }

    error InvalidSources();
    error InvalidParams();
    error BreakerTripped(TripReason reason);
    error PriceStale(uint256 lastAcceptedAt);

    event Checked(uint256 medianE18, uint256 agreeing, Reading[] readings);
    event PriceAccepted(uint256 priceE18);
    event Tripped(TripReason reason, uint256 medianE18);
    event Reset(uint256 priceE18);

    IPriceSource[] private sources;
    uint256[] private maxAges;

    uint256 public immutable QUORUM;
    uint256 public immutable MAX_DEVIATION_BPS;
    uint256 public immutable MAX_CHANGE_BPS;
    uint256 public immutable COOLDOWN;
    uint256 public immutable MAX_PRICE_AGE;
    uint256 public immutable MIN_PRICE_E18;
    uint256 public immutable MAX_PRICE_E18;

    uint256 public lastPrice;
    uint256 public lastPriceAt;
    TripReason public tripReason;
    /// @notice Time of the most recent unhealthy check while tripped; the cooldown counts from here.
    uint256 public trippedAt;

    /// @param sources_ Price sources, all quoting the same pair.
    /// @param maxAges_ Per-source maximum age in seconds (providers update on different cadences).
    constructor(IPriceSource[] memory sources_, uint256[] memory maxAges_, Params memory params) {
        if (sources_.length == 0 || sources_.length > MAX_SOURCES || sources_.length != maxAges_.length) {
            revert InvalidSources();
        }
        // A strict majority is required so two disjoint groups can never both reach quorum.
        if (params.quorum * 2 <= sources_.length || params.quorum > sources_.length) revert InvalidParams();
        if (params.maxDeviationBps == 0 || params.maxChangeBps == 0) revert InvalidParams();
        if (params.minPriceE18 == 0 || params.minPriceE18 >= params.maxPriceE18) revert InvalidParams();

        for (uint256 i = 0; i < sources_.length; i++) {
            if (address(sources_[i]) == address(0) || maxAges_[i] == 0) revert InvalidSources();
            sources.push(sources_[i]);
            maxAges.push(maxAges_[i]);
        }

        QUORUM = params.quorum;
        MAX_DEVIATION_BPS = params.maxDeviationBps;
        MAX_CHANGE_BPS = params.maxChangeBps;
        COOLDOWN = params.cooldown;
        MAX_PRICE_AGE = params.maxPriceAge;
        MIN_PRICE_E18 = params.minPriceE18;
        MAX_PRICE_E18 = params.maxPriceE18;
    }

    /// @notice The last accepted price. Reverts while the breaker is tripped or the price is stale.
    function price() external view returns (uint256) {
        if (tripReason != TripReason.None) revert BreakerTripped(tripReason);
        if (lastPriceAt == 0 || block.timestamp - lastPriceAt > MAX_PRICE_AGE) revert PriceStale(lastPriceAt);
        return lastPrice;
    }

    function isTripped() external view returns (bool) {
        return tripReason != TripReason.None;
    }

    function sourceCount() external view returns (uint256) {
        return sources.length;
    }

    function sourceAt(uint256 index) external view returns (IPriceSource source, uint256 maxAge) {
        return (sources[index], maxAges[index]);
    }

    /// @notice Classifies every source without changing state. `median` is 0 if no source is usable.
    function inspect() public view returns (Reading[] memory readings, uint256 median, uint256 agreeing) {
        uint256 n = sources.length;
        readings = new Reading[](n);
        uint256[] memory valid = new uint256[](n);
        uint256 validCount;

        for (uint256 i = 0; i < n; i++) {
            readings[i] = _read(i);
            if (readings[i].status == Status.Ok) valid[validCount++] = readings[i].priceE18;
        }
        if (validCount == 0) return (readings, 0, 0);

        median = _median(valid, validCount);
        for (uint256 i = 0; i < n; i++) {
            if (readings[i].status != Status.Ok) continue;
            if (_deviationBps(readings[i].priceE18, median) > MAX_DEVIATION_BPS) {
                readings[i].status = Status.Outlier;
            } else {
                agreeing++;
            }
        }
    }

    /// @notice Runs the check and records the outcome. Permissionless and never reverts.
    function poke() external returns (bool healthy) {
        (Reading[] memory readings, uint256 median, uint256 agreeing) = inspect();
        emit Checked(median, agreeing, readings);

        bool quorumMet = agreeing >= QUORUM;

        if (tripReason != TripReason.None) {
            if (!quorumMet) {
                trippedAt = block.timestamp;
                return false;
            }
            if (block.timestamp < trippedAt + COOLDOWN) return false;

            // Healthy for a full cooldown: the move is real, so re-anchor on it.
            tripReason = TripReason.None;
            _accept(median);
            emit Reset(median);
            return true;
        }

        if (!quorumMet) {
            _trip(TripReason.NoQuorum, median);
            return false;
        }
        if (lastPrice != 0 && _deviationBps(median, lastPrice) > MAX_CHANGE_BPS) {
            _trip(TripReason.ExcessiveChange, median);
            return false;
        }

        _accept(median);
        return true;
    }

    function _read(uint256 i) private view returns (Reading memory r) {
        try sources[i].latest() returns (uint256 p, uint256 updatedAt) {
            r.priceE18 = p;
            r.updatedAt = updatedAt;
            // A timestamp slightly ahead of consensus time is clock skew, not staleness.
            if (updatedAt < block.timestamp && block.timestamp - updatedAt > maxAges[i]) {
                r.status = Status.Stale;
            } else if (p < MIN_PRICE_E18 || p > MAX_PRICE_E18) {
                r.status = Status.OutOfBounds;
            } else {
                r.status = Status.Ok;
            }
        } catch {
            r.status = Status.Reverted;
        }
    }

    function _accept(uint256 median) private {
        lastPrice = median;
        lastPriceAt = block.timestamp;
        emit PriceAccepted(median);
    }

    function _trip(TripReason reason, uint256 median) private {
        tripReason = reason;
        trippedAt = block.timestamp;
        emit Tripped(reason, median);
    }

    /// @dev Insertion sort on at most MAX_SOURCES elements.
    function _median(uint256[] memory values, uint256 count) private pure returns (uint256) {
        for (uint256 i = 1; i < count; i++) {
            uint256 key = values[i];
            uint256 j = i;
            while (j > 0 && values[j - 1] > key) {
                values[j] = values[j - 1];
                j--;
            }
            values[j] = key;
        }
        uint256 mid = count / 2;
        return count % 2 == 1 ? values[mid] : (values[mid - 1] + values[mid]) / 2;
    }

    function _deviationBps(uint256 value, uint256 anchor) private pure returns (uint256) {
        uint256 diff = value > anchor ? value - anchor : anchor - value;
        return diff * BPS / anchor;
    }
}

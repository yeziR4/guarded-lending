// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Subset of the Hedera Schedule Service system contract (0x16b) used for HIP-1215
///         generalized scheduled contract calls.
interface IHederaScheduleService {
    /// @param to Contract to call at `expirySecond`.
    /// @param expirySecond Consensus second at which the call executes.
    /// @param gasLimit Gas for the scheduled call; the scheduling contract pays for it.
    /// @param value Tinybars to send with the call.
    /// @param callData ABI-encoded call.
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes memory callData)
        external
        returns (int64 responseCode, address scheduleAddress);

    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool hasCapacity);
}

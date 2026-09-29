// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Records bookings in place of the HSS system contract at 0x16b.
contract MockScheduleService {
    int64 public responseCode = 22;
    bool public hasCapacity = true;
    bool public exhaustGas;
    uint256 public scheduled;

    address public lastTo;
    uint256 public lastExpiry;
    uint256 public lastGasLimit;
    bytes public lastCallData;

    function setResponseCode(int64 rc) external {
        responseCode = rc;
    }

    function setHasCapacity(bool value) external {
        hasCapacity = value;
    }

    function setExhaustGas(bool value) external {
        exhaustGas = value;
    }

    function hasScheduleCapacity(uint256, uint256) external view returns (bool) {
        return hasCapacity;
    }

    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64, bytes memory callData)
        external
        returns (int64, address)
    {
        if (exhaustGas) {
            while (true) { } // runs out of whatever gas it was given
        }
        if (responseCode != 22) return (responseCode, address(0));
        scheduled++;
        lastTo = to;
        lastExpiry = expirySecond;
        lastGasLimit = gasLimit;
        lastCallData = callData;
        return (22, address(uint160(0x5c4ed + scheduled)));
    }
}

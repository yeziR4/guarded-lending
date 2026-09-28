// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Decimals
/// @notice Normalizes provider-specific fixed-point prices to 18 decimals.
library Decimals {
    uint256 internal constant TARGET = 18;

    error DecimalsOutOfRange(uint256 decimals);

    /// @notice Scales `value` expressed with `decimals` decimals to 18 decimals.
    function toE18(uint256 value, uint256 decimals) internal pure returns (uint256) {
        if (decimals > 36) revert DecimalsOutOfRange(decimals);
        if (decimals <= TARGET) return value * 10 ** (TARGET - decimals);
        return value / 10 ** (decimals - TARGET);
    }

    /// @notice Scales a Pyth-style `value * 10^expo` to 18 decimals.
    function expToE18(uint256 value, int32 expo) internal pure returns (uint256) {
        if (expo >= 0) return value * 10 ** (TARGET + uint256(int256(expo)));
        return toE18(value, uint256(-int256(expo)));
    }
}

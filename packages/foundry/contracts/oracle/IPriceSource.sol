// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPriceSource
/// @notice One oracle provider's view of a single price, normalized to 18 decimals.
/// @dev Implementations revert on data the provider itself marks as unusable (non-positive answer,
///      incomplete round, excessive confidence interval). Freshness and cross-source agreement are
///      judged by `OracleGuard`, not here, so every source is held to the same rules.
interface IPriceSource {
    error SourceInvalidAnswer();
    error SourceIncompleteRound();

    /// @return priceE18 Price with 18 decimals.
    /// @return updatedAt Unix timestamp (seconds) of the provider's last update.
    function latest() external view returns (uint256 priceE18, uint256 updatedAt);

    /// @notice Human-readable provider label shown in the UI and audit log.
    function label() external view returns (string memory);
}

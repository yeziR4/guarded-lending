// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPriceSource
/// @notice One provider's price, normalized to 18 decimals. Revert on data the provider marks unusable;
///         leave freshness and agreement to `OracleGuard`.
interface IPriceSource {
    error SourceInvalidAnswer();
    error SourceIncompleteRound();

    function latest() external view returns (uint256 priceE18, uint256 updatedAt);

    function label() external view returns (string memory);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceSource } from "../IPriceSource.sol";
import { Decimals } from "../Decimals.sol";

interface IChainlinkAggregator {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title ChainlinkSource
/// @notice Reads a Chainlink push feed (e.g. HBAR/USD) through `latestRoundData`.
contract ChainlinkSource is IPriceSource {
    IChainlinkAggregator public immutable FEED;
    uint8 private immutable FEED_DECIMALS;

    constructor(address feed) {
        FEED = IChainlinkAggregator(feed);
        FEED_DECIMALS = FEED.decimals();
    }

    function latest() external view returns (uint256 priceE18, uint256 updatedAt) {
        (, int256 answer,, uint256 roundUpdatedAt,) = FEED.latestRoundData();
        if (answer <= 0) revert SourceInvalidAnswer();
        if (roundUpdatedAt == 0) revert SourceIncompleteRound();

        return (Decimals.toE18(uint256(answer), FEED_DECIMALS), roundUpdatedAt);
    }

    function label() external pure returns (string memory) {
        return "Chainlink";
    }
}

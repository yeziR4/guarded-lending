// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceSource } from "../IPriceSource.sol";
import { Decimals } from "../Decimals.sol";

interface ISupraSValueFeed {
    struct PriceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    function getSvalue(uint256 pairIndex) external view returns (PriceFeed memory);
}

/// @title SupraSource
/// @notice Supra push-oracle pair. On Hedera HBAR is quoted in USDT; the guard's tolerance absorbs the basis.
contract SupraSource is IPriceSource {
    /// @dev Supra on Hedera reports millisecond timestamps.
    uint256 private constant MS_PER_SECOND = 1000;

    ISupraSValueFeed public immutable FEED;
    uint256 public immutable PAIR_INDEX;

    constructor(address feed, uint256 pairIndex) {
        FEED = ISupraSValueFeed(feed);
        PAIR_INDEX = pairIndex;
    }

    function latest() external view returns (uint256 priceE18, uint256 updatedAt) {
        ISupraSValueFeed.PriceFeed memory feed = FEED.getSvalue(PAIR_INDEX);
        if (feed.price == 0) revert SourceInvalidAnswer();
        if (feed.time == 0) revert SourceIncompleteRound();

        return (Decimals.toE18(feed.price, feed.decimals), feed.time / MS_PER_SECOND);
    }

    function label() external pure returns (string memory) {
        return "Supra";
    }
}

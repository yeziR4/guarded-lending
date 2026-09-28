// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceSource } from "../IPriceSource.sol";
import { Decimals } from "../Decimals.sol";
import { IPyth } from "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @title PythSource
/// @notice Reads a Pyth pull-oracle price. Pyth prices only move on-chain when someone submits a
///         signed Hermes update to the Pyth contract, so this source goes stale unless the app pushes
///         updates; the guard simply excludes it while stale.
contract PythSource is IPriceSource {
    uint256 private constant BPS = 10_000;

    error SourceConfidenceTooWide(uint256 confBps);

    IPyth public immutable PYTH;
    bytes32 public immutable PRICE_ID;
    /// @notice Largest accepted confidence interval, as basis points of the price.
    uint256 public immutable MAX_CONF_BPS;

    constructor(address pyth, bytes32 priceId, uint256 maxConfBps) {
        PYTH = IPyth(pyth);
        PRICE_ID = priceId;
        MAX_CONF_BPS = maxConfBps;
    }

    function latest() external view returns (uint256 priceE18, uint256 updatedAt) {
        // Freshness is enforced uniformly by the guard, so read without Pyth's own age check.
        PythStructs.Price memory p = PYTH.getPriceUnsafe(PRICE_ID);
        if (p.price <= 0) revert SourceInvalidAnswer();
        if (p.publishTime == 0) revert SourceIncompleteRound();

        uint256 price = uint256(uint64(p.price));
        uint256 confBps = uint256(p.conf) * BPS / price;
        if (confBps > MAX_CONF_BPS) revert SourceConfidenceTooWide(confBps);

        return (Decimals.expToE18(price, p.expo), p.publishTime);
    }

    function label() external pure returns (string memory) {
        return "Pyth";
    }
}

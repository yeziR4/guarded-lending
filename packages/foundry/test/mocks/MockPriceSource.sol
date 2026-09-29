// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { IPriceSource } from "../../contracts/oracle/IPriceSource.sol";

/// @notice Price source whose price, timestamp and failure mode the test controls.
contract MockPriceSource is IPriceSource {
    string private name;
    uint256 public priceE18;
    uint256 public updatedAt;
    bool public reverts;

    constructor(string memory name_, uint256 priceE18_) {
        name = name_;
        set(priceE18_);
    }

    function set(uint256 priceE18_) public {
        priceE18 = priceE18_;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function setReverts(bool reverts_) external {
        reverts = reverts_;
    }

    function latest() external view returns (uint256, uint256) {
        if (reverts) revert SourceInvalidAnswer();
        return (priceE18, updatedAt);
    }

    function label() external view returns (string memory) {
        return name;
    }
}

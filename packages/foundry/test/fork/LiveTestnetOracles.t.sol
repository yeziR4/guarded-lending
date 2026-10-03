// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { OracleGuard } from "../../contracts/oracle/OracleGuard.sol";
import { IPriceSource } from "../../contracts/oracle/IPriceSource.sol";
import { ChainlinkSource } from "../../contracts/oracle/sources/ChainlinkSource.sol";
import { SupraSource } from "../../contracts/oracle/sources/SupraSource.sol";
import { PythSource } from "../../contracts/oracle/sources/PythSource.sol";

/// @notice Real sources and guard against live testnet feeds. Skipped unless forked (`test:testnet`).
contract LiveTestnetOraclesTest is Test {
    address internal constant CHAINLINK_HBAR_USD = 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a;
    address internal constant SUPRA_PUSH_ORACLE = 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917;
    address internal constant PYTH = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729;
    bytes32 internal constant PYTH_HBAR_USD = 0x3728e591097635310e6341af53db8b7ee42da9b3a8d918f9463ce9cca886dfbd;

    OracleGuard internal guard;

    function setUp() public {
        if (block.chainid != 296 || CHAINLINK_HBAR_USD.code.length == 0) vm.skip(true);

        IPriceSource[] memory sources = new IPriceSource[](3);
        sources[0] = new ChainlinkSource(CHAINLINK_HBAR_USD);
        sources[1] = new SupraSource(SUPRA_PUSH_ORACLE, 75);
        sources[2] = new PythSource(PYTH, PYTH_HBAR_USD, 200);
        uint256[] memory ages = new uint256[](3);
        ages[0] = 25 hours;
        ages[1] = 3 hours;
        ages[2] = 10 minutes;

        guard = new OracleGuard(
            sources,
            ages,
            OracleGuard.Params({
                quorum: 2,
                maxDeviationBps: 500,
                maxChangeBps: 2000,
                cooldown: 30 minutes,
                maxPriceAge: 2 hours,
                minPriceE18: 0.001e18,
                maxPriceE18: 100e18
            })
        );
    }

    function test_liveFeeds_reachQuorum() public {
        (OracleGuard.Reading[] memory readings, uint256 median, uint256 agreeing) = guard.inspect();

        for (uint256 i = 0; i < readings.length; i++) {
            (IPriceSource source,) = guard.sourceAt(i);
            emit log_named_decimal_uint(source.label(), readings[i].priceE18, 18);
            emit log_named_uint(
                "  status (0=Ok 1=Reverted 2=Stale 3=OutOfBounds 4=Outlier)", uint256(readings[i].status)
            );
        }
        emit log_named_decimal_uint("median", median, 18);

        assertEq(uint256(readings[0].status), uint256(OracleGuard.Status.Ok), "Chainlink live");
        assertEq(uint256(readings[1].status), uint256(OracleGuard.Status.Ok), "Supra live");
        assertGe(agreeing, 2);
        assertTrue(guard.poke());
    }
}

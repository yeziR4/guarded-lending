//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { IPriceSource } from "../contracts/oracle/IPriceSource.sol";
import { OracleGuard } from "../contracts/oracle/OracleGuard.sol";
import { ChainlinkSource } from "../contracts/oracle/sources/ChainlinkSource.sol";
import { SupraSource } from "../contracts/oracle/sources/SupraSource.sol";
import { PythSource } from "../contracts/oracle/sources/PythSource.sol";
import { LendingMarket } from "../contracts/LendingMarket.sol";
import { Guardian } from "../contracts/Guardian.sol";

/**
 * @notice Deploys the sources, guard, market and Guardian. HTS/HSS calls run afterwards in `npm run setup`
 *         (forge script simulation has no system contracts). Tunables are overridable by env var.
 */
contract DeployScript is ScaffoldETHDeploy {
    struct Feeds {
        address chainlinkHbarUsd;
        address supraPushOracle;
        uint256 supraHbarUsdtPair;
        address pyth;
        bytes32 pythHbarUsdId;
        address usdc;
    }

    error UnsupportedChain(uint256 chainId);

    // Sources: docs.chain.link (Hedera), docs.supra.com (push oracle networks + pair index),
    // docs.pyth.network (EVM addresses + price feed IDs), developers.circle.com (USDC on Hedera).
    function _feeds() internal view returns (Feeds memory) {
        if (block.chainid == 296) {
            return Feeds({
                chainlinkHbarUsd: 0x59bC155EB6c6C415fE43255aF66EcF0523c92B4a,
                supraPushOracle: 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917,
                supraHbarUsdtPair: 75,
                pyth: 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729,
                pythHbarUsdId: 0x3728e591097635310e6341af53db8b7ee42da9b3a8d918f9463ce9cca886dfbd,
                usdc: 0x0000000000000000000000000000000000068cDa // 0.0.429274
            });
        }
        if (block.chainid == 295) {
            return Feeds({
                chainlinkHbarUsd: 0xAF685FB45C12b92b5054ccb9313e135525F9b5d5,
                supraPushOracle: 0xD02cc7a670047b6b012556A88e275c685d25e0c9,
                supraHbarUsdtPair: 75,
                pyth: 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729,
                pythHbarUsdId: 0x3728e591097635310e6341af53db8b7ee42da9b3a8d918f9463ce9cca886dfbd,
                usdc: 0x000000000000000000000000000000000006f89a // 0.0.456858
            });
        }
        revert UnsupportedChain(block.chainid);
    }

    function run() external ScaffoldEthDeployerRunner {
        Feeds memory feeds = _feeds();

        IPriceSource[] memory sources = new IPriceSource[](3);
        sources[0] = new ChainlinkSource(feeds.chainlinkHbarUsd);
        sources[1] = new SupraSource(feeds.supraPushOracle, feeds.supraHbarUsdtPair);
        sources[2] = new PythSource(feeds.pyth, feeds.pythHbarUsdId, vm.envOr("PYTH_MAX_CONF_BPS", uint256(200)));

        uint256[] memory maxAges = new uint256[](3);
        // Heartbeat plus margin: Chainlink HBAR/USD on Hedera updates on a 0.5% move or every 24 h.
        maxAges[0] = vm.envOr("CHAINLINK_MAX_AGE", uint256(25 hours));
        maxAges[1] = vm.envOr("SUPRA_MAX_AGE", uint256(3 hours));
        // Pyth is pull-based: it is only as fresh as the last update someone pushed.
        maxAges[2] = vm.envOr("PYTH_MAX_AGE", uint256(10 minutes));

        OracleGuard guard = new OracleGuard(
            sources,
            maxAges,
            OracleGuard.Params({
                quorum: vm.envOr("GUARD_QUORUM", uint256(2)),
                maxDeviationBps: vm.envOr("GUARD_MAX_DEVIATION_BPS", uint256(500)),
                maxChangeBps: vm.envOr("GUARD_MAX_CHANGE_BPS", uint256(2000)),
                cooldown: vm.envOr("GUARD_COOLDOWN", uint256(30 minutes)),
                maxPriceAge: vm.envOr("GUARD_MAX_PRICE_AGE", uint256(2 hours)),
                minPriceE18: vm.envOr("GUARD_MIN_PRICE_E18", uint256(0.001e18)),
                maxPriceE18: vm.envOr("GUARD_MAX_PRICE_E18", uint256(100e18))
            })
        );

        LendingMarket market = new LendingMarket(
            vm.envOr("LENDING_ASSET", feeds.usdc), // 6-decimal HTS stablecoin
            6,
            guard,
            LendingMarket.RiskParams({
                ltvBps: 6500,
                liquidationThresholdBps: 8000,
                liquidationBonusBps: 500,
                closeFactorBps: 5000,
                baseRatePerSecond: 634_195_839, // ~2% APR
                slopePerSecond: 6_341_958_396 // +20% APR at full utilization
            })
        );

        Guardian guardian = new Guardian(
            guard,
            market,
            vm.envOr("GUARDIAN_INTERVAL", uint256(12 hours)),
            vm.envOr("GUARDIAN_GAS_LIMIT", uint256(2_000_000))
        );

        deployments.push(Deployment({ name: "ChainlinkSource", addr: address(sources[0]) }));
        deployments.push(Deployment({ name: "SupraSource", addr: address(sources[1]) }));
        deployments.push(Deployment({ name: "PythSource", addr: address(sources[2]) }));
        deployments.push(Deployment({ name: "OracleGuard", addr: address(guard) }));
        deployments.push(Deployment({ name: "LendingMarket", addr: address(market) }));
        deployments.push(Deployment({ name: "Guardian", addr: address(guardian) }));
    }
}

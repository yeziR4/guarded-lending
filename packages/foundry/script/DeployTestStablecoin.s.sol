//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { TestStablecoin } from "../contracts/TestStablecoin.sol";

/**
 * @notice Testnet only: deploys the tUSD faucet. Then call `initialize()` with ~30 HBAR (the unused part is refunded),
 *         and deploy the market with `LENDING_ASSET=<token address>`.
 */
contract DeployTestStablecoinScript is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        deployments.push(Deployment({ name: "TestStablecoin", addr: address(new TestStablecoin()) }));
    }
}

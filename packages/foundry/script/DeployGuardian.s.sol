//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { OracleGuard } from "../contracts/oracle/OracleGuard.sol";
import { LendingMarket } from "../contracts/LendingMarket.sol";
import { Guardian } from "../contracts/Guardian.sol";

/**
 * @notice Deploys a new Guardian for the OracleGuard and LendingMarket already recorded in
 *         deployments/<chainId>.json, e.g. to change its interval or gas limit. Run `npm run setup` after
 *         to fund and start it (the previous Guardian simply stops once its funding runs out).
 */
contract DeployGuardianScript is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        Guardian guardian = new Guardian(
            OracleGuard(deployedAddress("OracleGuard")),
            LendingMarket(deployedAddress("LendingMarket")),
            vm.envOr("GUARDIAN_INTERVAL", uint256(1 hours)),
            vm.envOr("GUARDIAN_GAS_LIMIT", uint256(400_000))
        );
        deployments.push(Deployment({ name: "Guardian", addr: address(guardian) }));
    }
}

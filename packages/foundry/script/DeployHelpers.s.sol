//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";

contract ScaffoldETHDeploy is Script {
    error InvalidChain();
    error DeployerHasNoBalance();
    error InvalidPrivateKey(string);

    event AnvilSetBalance(address account, uint256 amount);
    event FailedAnvilRequest();

    struct Deployment {
        string name;
        address addr;
    }

    string root;
    string path;
    Deployment[] public deployments;
    uint256 constant ANVIL_BASE_BALANCE = 10000 ether;

    /// @notice The deployer address for every run
    address deployer;

    /// @notice Use this modifier on your run() function on your deploy scripts
    modifier ScaffoldEthDeployerRunner() {
        deployer = _startBroadcast();
        if (deployer == address(0)) {
            revert InvalidPrivateKey("Invalid private key");
        }
        _;
        _stopBroadcast();
        exportDeployments();
    }

    function _startBroadcast() internal returns (address) {
        vm.startBroadcast();
        (, address _deployer,) = vm.readCallers();

        if (block.chainid == 31337 && _deployer.balance == 0) {
            try vm.deal(_deployer, ANVIL_BASE_BALANCE) {
                emit AnvilSetBalance(_deployer, ANVIL_BASE_BALANCE);
            } catch {
                emit FailedAnvilRequest();
            }
        }
        return _deployer;
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }

    function exportDeployments() internal {
        // fetch already existing contracts
        root = vm.projectRoot();
        path = string.concat(root, "/deployments/");
        // The Makefile creates this folder, but plain `forge script` runs (e.g. Windows without make) do not.
        vm.createDir(path, true);
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory jsonWrite;

        // Keep contracts recorded by earlier runs (e.g. DeployGuardian after Deploy) unless this run
        // redeployed a contract with the same name.
        if (vm.exists(path)) {
            string memory existing = vm.readFile(path);
            string[] memory keys = vm.parseJsonKeys(existing, "$");
            for (uint256 i = 0; i < keys.length; i++) {
                if (bytes(keys[i]).length != 42) continue; // skip "networkName"
                string memory name = vm.parseJsonString(existing, string.concat(".", keys[i]));
                if (!_deployedThisRun(name)) vm.serializeString(jsonWrite, keys[i], name);
            }
        }

        uint256 len = deployments.length;

        for (uint256 i = 0; i < len; i++) {
            vm.serializeString(jsonWrite, vm.toString(deployments[i].addr), deployments[i].name);
        }

        string memory chainName;

        try vm.getChain(block.chainid) returns (Vm.Chain memory chain) {
            chainName = chain.name;
        } catch {
            chainName = findChainName();
        }
        jsonWrite = vm.serializeString(jsonWrite, "networkName", chainName);
        vm.writeJson(jsonWrite, path);
    }

    function _deployedThisRun(string memory name) private view returns (bool) {
        for (uint256 i = 0; i < deployments.length; i++) {
            if (keccak256(bytes(deployments[i].name)) == keccak256(bytes(name))) return true;
        }
        return false;
    }

    /// @notice Address of a contract recorded in deployments/<chainId>.json by an earlier run.
    function deployedAddress(string memory name) internal view returns (address) {
        string memory file = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(file);
        string[] memory keys = vm.parseJsonKeys(json, "$");
        for (uint256 i = 0; i < keys.length; i++) {
            if (bytes(keys[i]).length != 42) continue;
            if (keccak256(bytes(vm.parseJsonString(json, string.concat(".", keys[i])))) == keccak256(bytes(name))) {
                return vm.parseAddress(keys[i]);
            }
        }
        revert(string.concat(name, " not found in ", file));
    }

    function findChainName() public returns (string memory) {
        uint256 thisChainId = block.chainid;
        string[2][] memory allRpcUrls = vm.rpcUrls();
        for (uint256 i = 0; i < allRpcUrls.length; i++) {
            try vm.createSelectFork(allRpcUrls[i][1]) {
                if (block.chainid == thisChainId) {
                    return allRpcUrls[i][0];
                }
            } catch {
                continue;
            }
        }
        revert InvalidChain();
    }
}

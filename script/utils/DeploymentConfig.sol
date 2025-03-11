// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

abstract contract DeploymentConfig is Script {

    function readContractAddress(string memory contractName) internal returns (address contractAddress) {
        string memory deploymentDir = string.concat(
            vm.projectRoot(),
            "/",
            "deployment",
            "/",
            vm.toString(block.chainid),
            ".json"
        );
        if (!vm.exists(deploymentDir)) {
            revert("Cannot find deployment file");
        }
        string memory jsonStr = vm.readFile(deploymentDir);
        contractAddress = stdJson.readAddress(jsonStr, string.concat(
            ".",
            contractName
        ));
    }

    function writeToJson(string memory contractName, address contractAddress) internal {
        string memory deploymentDir = string.concat(
            vm.projectRoot(),
            "/",
            "deployment"
        );

        // check dir exists
        if (!vm.exists(deploymentDir)) {
            vm.createDir(deploymentDir, false);
        }

        // deployment path
        string memory jsonPath = string.concat(
            deploymentDir,
            "/",
            vm.toString(block.chainid),
            ".json"
        );

        string memory jsonKey = "deployment key";
        string memory jsonStr = "";
        if (vm.exists(jsonPath)) {
            jsonStr = vm.readFile(jsonPath);
            vm.serializeJson(jsonKey, jsonStr);
        }
        
        string memory finalJson = vm.serializeAddress(jsonKey, contractName, contractAddress);
        vm.writeJson(finalJson, jsonPath);
    }
}
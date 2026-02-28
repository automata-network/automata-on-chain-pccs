// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Vm.sol";
import "forge-std/console.sol";

abstract contract Multichain {
    address constant HEVM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    Vm constant internalVm = Vm(HEVM_ADDRESS);

    bool useMultichain = internalVm.envOr("MULTICHAIN", false);

    modifier multichain() {
        if (useMultichain) {
            string[] memory emptyArr = new string[](0);
            string[] memory legacyChains = internalVm.envOr("CHAINS", ",", emptyArr);

            if (legacyChains.length > 0) {
                // Legacy mode: CHAINS + {NAME}_RPC_URL env vars
                for (uint256 i = 0; i < legacyChains.length; i++) {
                    string memory chain = legacyChains[i];
                    string memory rpcUrl = internalVm.envString(string.concat(chain, "_RPC_URL"));

                    try internalVm.createSelectFork(rpcUrl) {
                        internalVm.setEnv("RPC_URL", rpcUrl);
                        console.log("Running on chain: ", chain);
                        _;
                        internalVm.setEnv("RPC_URL", "");
                    } catch Error(string memory reason) {
                        console.log("Skipping chain: ", chain, " Reason: ", reason);
                    }
                }
            } else {
                // rpc_map mode: read chain IDs and RPC URLs from rpc_map file
                string memory rpcMapPath = string.concat(internalVm.projectRoot(), "/rpc_map");
                string memory rpcMapJson = internalVm.readFile(rpcMapPath);
                string[] memory allChainIds = internalVm.parseJsonKeys(rpcMapJson, "$");

                string[] memory chainIdsFilter = internalVm.envOr("CHAIN_IDS", ",", emptyArr);

                string[] memory targetChainIds;
                if (chainIdsFilter.length > 0) {
                    // Filtered mode: only deploy to specified chain IDs
                    targetChainIds = chainIdsFilter;
                } else {
                    // Safety guard: require ALL_CHAINS=true to deploy to all chains
                    bool allChains = internalVm.envOr("ALL_CHAINS", false);
                    require(
                        allChains,
                        "Set CHAIN_IDS=<ids> to select specific chains, or ALL_CHAINS=true to deploy to all chains in rpc_map"
                    );
                    targetChainIds = allChainIds;
                }

                for (uint256 i = 0; i < targetChainIds.length; i++) {
                    string memory chainId = targetChainIds[i];
                    string memory rpcUrl =
                        internalVm.parseJsonString(rpcMapJson, string.concat(".", chainId));

                    try internalVm.createSelectFork(rpcUrl) {
                        internalVm.setEnv("RPC_URL", rpcUrl);
                        console.log("Running on chain ID: ", chainId);
                        _;
                        internalVm.setEnv("RPC_URL", "");
                    } catch Error(string memory reason) {
                        console.log("Skipping chain ID: ", chainId, " Reason: ", reason);
                    }
                }
            }
        } else {
            _;
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/helper/EnclaveIdentityHelper.sol";
import "../../src/helper/FmspcTcbHelper.sol";
import "../../src/helper/PCKHelper.sol";
import "../../src/helper/X509CRLHelper.sol";

contract DeployHelpers is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    function deployEnclaveIdentityHelper() public {
        vm.startBroadcast(privateKey);
        EnclaveIdentityHelper enclaveIdentityHelper = new EnclaveIdentityHelper();
        console.log("[LOG] EnclaveIdentityHelper: ", address(enclaveIdentityHelper));
        vm.stopBroadcast();
    }

    function deployFmspcTcbHelper() public {
        vm.startBroadcast(privateKey);
        FmspcTcbHelper fmspcTcbHelper = new FmspcTcbHelper();
        console.log("[LOG] FmspcTcbHelper: ", address(fmspcTcbHelper));
        vm.stopBroadcast();
    }

    function deployPckHelper() public {
        vm.startBroadcast(privateKey);
        PCKHelper pckHelper = new PCKHelper();
        console.log("[LOG] PCKHelper: ", address(pckHelper));
        vm.stopBroadcast();
    }

    function deployX509CrlHelper() public {
        vm.startBroadcast(privateKey);
        X509CRLHelper x509Helper = new X509CRLHelper();
        console.log("[LOG] X509CRLHelper: ", address(x509Helper));
        vm.stopBroadcast();
    }
}
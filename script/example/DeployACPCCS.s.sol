// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/examples/AccessControlledPCCS.sol";

contract DeployACPCCS is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address x509Crl = vm.envAddress("X509_CRL_HELPER");
    address x509 = vm.envAddress("X509_HELPER");
    address enclaveIdentityHelper = vm.envAddress("ENCLAVE_IDENTITY_HELPER");
    address fmspcTcbHelper = vm.envAddress("FMSPC_TCB_HELPER");

    function run() public {
        vm.startBroadcast(privateKey);

        AccessControlledPCCS pccs = new AccessControlledPCCS(enclaveIdentityHelper, fmspcTcbHelper, x509, x509Crl);

        console.log("[LOG] AccessControlledPCCS: ", address(pccs));

        vm.stopBroadcast();
    }
}

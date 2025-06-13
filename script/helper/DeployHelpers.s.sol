// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/helpers/EnclaveIdentityHelper.sol";
import "../../src/helpers/FmspcTcbHelper.sol";
import "../../src/helpers/PCKHelper.sol";
import "../../src/helpers/X509CRLHelper.sol";
import "../../src/helpers/TcbEvalHelper.sol";
import "../utils/Salt.sol";
import "../utils/DeploymentConfig.sol";

contract DeployHelpers is DeploymentConfig {
    address owner = vm.envAddress("OWNER");

    function run() public {
        deployEnclaveIdentityHelper();
        deployFmspcTcbHelper();
        deployPckHelper();
        deployX509CrlHelper();
        deployTcbEvalHelper();
    }

    function deployEnclaveIdentityHelper() public {
        vm.startBroadcast();
        EnclaveIdentityHelper enclaveIdentityHelper = new EnclaveIdentityHelper{salt: ENCLAVE_IDENTITY_HELPER_SALT}();
        console.log("[LOG] EnclaveIdentityHelper: ", address(enclaveIdentityHelper));
        vm.stopBroadcast();

        writeToJson("EnclaveIdentityHelper", address(enclaveIdentityHelper));
    }

    function deployFmspcTcbHelper() public {
        vm.startBroadcast(owner);
        FmspcTcbHelper fmspcTcbHelper = new FmspcTcbHelper{salt: FMSPC_TCB_HELPER_SALT}();
        console.log("[LOG] FmspcTcbHelper: ", address(fmspcTcbHelper));
        vm.stopBroadcast();

        writeToJson("FmspcTcbHelper", address(fmspcTcbHelper));
    }

    function deployPckHelper() public {
        vm.startBroadcast(owner);
        PCKHelper pckHelper = new PCKHelper{salt: X509_HELPER_SALT}();
        console.log("[LOG] PCKHelper/X509Helper: ", address(pckHelper));
        vm.stopBroadcast();

        writeToJson("PCKHelper", address(pckHelper));
    }

    function deployX509CrlHelper() public {
        vm.startBroadcast(owner);
        X509CRLHelper x509Helper = new X509CRLHelper{salt: X509_CRL_HELPER_SALT}();
        console.log("[LOG] X509CRLHelper: ", address(x509Helper));
        vm.stopBroadcast();

        writeToJson("X509CRLHelper", address(x509Helper));
    }

    function deployTcbEvalHelper() public {
        vm.startBroadcast(owner);
        TcbEvalHelper tcbEvalHelper = new TcbEvalHelper{salt: TCB_EVAL_HELPER_SALT}();
        console.log("[LOG] TcbEvalHelper: ", address(tcbEvalHelper));
        vm.stopBroadcast();

        writeToJson("TcbEvalHelper", address(tcbEvalHelper));
    }
}

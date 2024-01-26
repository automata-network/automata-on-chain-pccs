// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/verax/portals/PcsDaoPortal.sol";
import "../../src/verax/portals/EnclaveIdentityDaoPortal.sol";
import "../../src/verax/portals/FmspcTcbDaoPortal.sol";
import "../../src/verax/portals/PckDaoPortal.sol";

/**
 * =================================================================
 * !!! IMPORTANT DO NOT IGNORE !!!
 * You run source .env BEFORE running each deployment functions
 * After executing each deployment, remember to update the .env file
 * =================================================================
 */
contract DeployVeraxPortal is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address router = vm.envAddress("ROUTER_ADDRESS");

    address pcs = vm.envAddress("PCS_DAO_PORTAL");

    address x509Crl = vm.envAddress("X509_CRL_HELPER");
    address x509 = vm.envAddress("X509_HELPER");
    address enclaveIdentityHelper = vm.envAddress("ENCLAVE_IDENTITY_HELPER");
    address fmspcTcbHelper = vm.envAddress("FMSPC_TCB_HELPER");

    function deployPcsDaoPortal() public {
        vm.startBroadcast(privateKey);

        address[] memory blank;
        PcsDaoPortal pcsDao = new PcsDaoPortal(blank, router, x509, x509Crl);
        console.log("[LOG] PcsDaoPortal: ", address(pcsDao));

        vm.stopBroadcast();
    }

    function deployEnclaveIdentityDaoPortal() public {
        vm.startBroadcast(privateKey);

        address[] memory blank;
        EnclaveIdentityDaoPortal enclaveIdentity =
            new EnclaveIdentityDaoPortal(blank, router, pcs, enclaveIdentityHelper, x509);
        console.log("[LOG] PcsDaoPortal: ", address(enclaveIdentity));

        vm.stopBroadcast();
    }

    function deployFmspcTcbDaoPortal() public {
        vm.startBroadcast(privateKey);

        address[] memory blank;
        FmspcTcbDaoPortal fmspcTcbDao = new FmspcTcbDaoPortal(blank, router, pcs, fmspcTcbHelper, x509);
        console.log("[LOG] FmspcTcbDaoPortal: ", address(fmspcTcbDao));

        vm.stopBroadcast();
    }

    function deployPckDaoPortal() public {
        vm.startBroadcast(privateKey);

        address[] memory blank;
        PckDaoPortal pckDao = new PckDaoPortal(blank, router, pcs, x509, x509Crl);
        console.log("[LOG] PckDaoPortal: ", address(pckDao));

        vm.stopBroadcast();
    }
}

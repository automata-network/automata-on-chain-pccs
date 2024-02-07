// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {SchemaRegistry} from "@consensys/linea-attestation-registry-contracts/SchemaRegistry.sol";
import {PortalRegistry} from "@consensys/linea-attestation-registry-contracts/PortalRegistry.sol";
import {ModuleRegistry} from "@consensys/linea-attestation-registry-contracts/ModuleRegistry.sol";
import {AttestationRegistry} from "@consensys/linea-attestation-registry-contracts/AttestationRegistry.sol";

contract ConfigureVerax is Script {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");

    address pcs = vm.envAddress("PCS_DAO_PORTAL");
    address enclaveIdentity = vm.envAddress("ENCLAVE_IDENTITY_DAO_PORTAL");
    address fmspcTcb = vm.envAddress("FMSPC_TCB_DAO_PORTAL");
    address pck = vm.envAddress("PCK_DAO_PORTAL");

    SchemaRegistry schemaRegistry = SchemaRegistry(vm.envAddress("SCHEMA_REGISTRY_ADDRESS"));
    PortalRegistry portalRegistry = PortalRegistry(vm.envAddress("PORTAL_REGISTRY_ADDRESS"));

    function registerSchemas() public {
        vm.startBroadcast(privateKey);

        _registerSchemas();

        vm.stopBroadcast();
    }

    function registerPortals() public {
        vm.startBroadcast(privateKey);

        _registerPortals();

        vm.stopBroadcast();
    }

    function _registerSchemas() private {
        // Enclave Identity Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS Enclave Identity", // name
            "", // Description
            "", // Context
            "uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string identity, bytes signature" // Schema
        );
        // FMSPC TCB Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS FMSPC TCB", // name
            "", // Description
            "", // Context
            "uint256 tcbType, uint256 version, uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string tcbInfo, bytes signature" // Schema
        );
        // PCK Certificate Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS PCK Certificate", // name
            "", // Description
            "", // Context
            "bytes pckCert" // Schema
        );
        // PCS Certificates Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS Certificates", // name
            "", // Description
            "", // Context
            "bytes pcsCert" // Schema
        );
        // PCS CRL Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS Certificate Revocation List", // name
            "", // Description
            "", // Context
            "bytes pcsCrl" // Schema
        );
        // Platform TCBs Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCCS Platform TCBs", // name
            "", // Description
            "", // Context
            "string tcbm" // Schema
        );
    }

    function _registerPortals() private {
        // portalRegistry.register(
        //     address(pcs),
        //     "Intel On Chain PCS Data Access Object Portal", // name
        //     "some-description", // description
        //     true, // isRevocable
        //     "some-owner" // ownerName
        // );
        // portalRegistry.register(
        //     address(enclaveIdentity),
        //     "Intel On Chain Enclave Identity Data Access Object Portal", // name
        //     "some-description", // description
        //     true, // isRevocable
        //     "some-owner" // ownerName
        // );
        // portalRegistry.register(
        //     address(fmspcTcb),
        //     "Intel On Chain FMPSC TCB Data Access Object Portal", // name
        //     "some-description", // description
        //     true, // isRevocable
        //     "some-owner" // ownerName
        // );
        portalRegistry.register(
            address(pck),
            "Intel On Chain PCK Data Access Object Portal", // name
            "some-description", // description
            true, // isRevocable
            "some-owner" // ownerName
        );
    }
}

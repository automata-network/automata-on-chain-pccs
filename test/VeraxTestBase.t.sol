// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {SchemaRegistry} from "@consensys/linea-attestation-registry-contracts/SchemaRegistry.sol";
import {PortalRegistry} from "@consensys/linea-attestation-registry-contracts/PortalRegistry.sol";
import {ModuleRegistry} from "@consensys/linea-attestation-registry-contracts/ModuleRegistry.sol";
import {AttestationRegistry} from "@consensys/linea-attestation-registry-contracts/AttestationRegistry.sol";

import {EnclaveIdentityHelper, EnclaveIdentityJsonObj} from "../src/helper/EnclaveIdentityHelper.sol";
import {FmspcTcbHelper, TcbInfoJsonObj} from "../src/helper/FmspcTcbHelper.sol";
import {X509CRLHelper, X509CRLObj} from "../src/helper/X509CRLHelper.sol";
import {PCKHelper, X509CertObj} from "../src/helper/PCKHelper.sol";

abstract contract VeraxTestBase is Test {
    EnclaveIdentityHelper enclaveIdentityLib;
    FmspcTcbHelper fsmpcTcbLib;
    X509CRLHelper x509CrlLib;
    PCKHelper x509Lib;
    address admin = address(1);

    address internal constant registryOwner = 0x39241A22eA7162C206409aAA2E4a56f9a79c15AB;
    string internal forkUrl = vm.envString("FORK_URL");
    address internal router = vm.envAddress("TEST_ROUTER_ADDRESS");
    PortalRegistry internal portalRegistry = PortalRegistry(vm.envAddress("TEST_PORTAL_REGISTRY_ADDRESS"));
    SchemaRegistry internal schemaRegistry = SchemaRegistry(vm.envAddress("TEST_SCHEMA_REGISTRY_ADDRESS"));
    ModuleRegistry internal moduleRegistry = ModuleRegistry(vm.envAddress("TEST_MODULE_REGISTRY_ADDRESS"));
    AttestationRegistry internal attestationRegistry =
        AttestationRegistry(vm.envAddress("TEST_ATTESTATION_REGISTRY_ADDRESS"));

    bytes32 internal constant ENCLAVE_IDENTITY_SCHEMA_ID =
        0xe9524a98e08b3e84ffe24d87c7571c870b2deb7ffbeea11aa3a11be287930d45;
    bytes32 internal constant FMSPC_TCB_SCHEMA_ID = 0xa757d8bdd4714c2f4894f419eb480be748eb303d5e3652dc97c21e38d916d750;
    bytes32 internal constant PCK_SCHEMA_ID = 0x24c1e0f0784350da3b36c4fc38e701b0218e02a9ec9eba3329d7bcafc339df2b;
    bytes32 internal constant PCS_CERT_SCHEMA_ID = 0xedc3e4f5846d93e65599fb22bc868cdb3ec6c766bbe6145acb2c3ab4765e0eb0;
    bytes32 internal constant PCS_CRL_SCHEMA_ID = 0x420573d190f658fca27d49a4c5568195f63283301f2fd65104f7704e9442b912;

    function setUp() public virtual {
        // Fork Linea mainnet
        uint256 fork = vm.createFork(forkUrl);
        vm.selectFork(fork);
        vm.deal(admin, 100 ether);

        // pinned January 20th, 2024 - 061323h UTC
        vm.warp(1705644803);

        // assign issuer role
        vm.prank(registryOwner);
        portalRegistry.setIssuer(admin);

        vm.startPrank(admin);

        // deploy helper libraries
        enclaveIdentityLib = new EnclaveIdentityHelper();
        fsmpcTcbLib = new FmspcTcbHelper();
        x509CrlLib = new X509CRLHelper();
        x509Lib = new PCKHelper();

        // registers schemas

        // Enclave Identity Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS Enclave Identity", // name
            "", // Description
            "", // Context
            "(uint8 id, uint256 version, uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, uint256 tcbEvaluationDataNumber, bytes4 miscselect, bytes4 miscselectMask, bytes16 attributes, bytes16 attributesMask, bytes32 mrsigner, uint16 isvprodid, (uint16 isvsvn, uint256 dateTimestamp, uint8 status)[] tcb), bytes32 digest, string identity, bytes signature" // Schema
        );
        // FMSPC TCB Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS FMSPC TCB", // name
            "", // Description
            "", // Context
            "uint256 tcbType, uint256 version, uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, (uint256 pcesvn, uin256[] cpusvnArrs, uint256 tcbDateTimestamp, uint8 status)[]tcbLevels, bytes32 digest, string tcbInfo, bytes signature" // Schema
        );
        // PCK Certificate Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS PCK Certificate", // name
            "", // Description
            "", // Context
            "bytes pckCert" // Schema
        );
        // PCS Certificates Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS Certificates", // name
            "", // Description
            "", // Context
            "bytes32 identifier, bytes pcsCert" // Schema
        );
        // PCS CRL Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS Certificate Revocation List", // name
            "", // Description
            "", // Context
            "bytes32 identifier, bytes pcsCrl" // Schema
        );
        // Platform TCBs Schema
        schemaRegistry.createSchema(
            "Intel On-Chain Platform TCBs", // name
            "", // Description
            "", // Context
            "string tcbm" // Schema
        );

        vm.stopPrank();
    }

    function testSetup() public {
        assertTrue(portalRegistry.isIssuer(admin));
        assertTrue(schemaRegistry.isRegistered(ENCLAVE_IDENTITY_SCHEMA_ID));
        assertTrue(schemaRegistry.isRegistered(FMSPC_TCB_SCHEMA_ID));
        assertTrue(schemaRegistry.isRegistered(PCK_SCHEMA_ID));
        assertTrue(schemaRegistry.isRegistered(PCS_CERT_SCHEMA_ID));
        assertTrue(schemaRegistry.isRegistered(PCS_CRL_SCHEMA_ID));
    }
}

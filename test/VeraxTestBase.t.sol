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
import {X509Helper, X509CertObj} from "../src/helper/X509Helper.sol";

abstract contract VeraxTestBase is Test {
    EnclaveIdentityHelper enclaveIdentityLib;
    FmspcTcbHelper fsmpcTcbLib;
    X509CRLHelper x509CrlLib;
    X509Helper x509Lib;
    address admin = address(1);

    address internal constant registryOwner = 0x39241A22eA7162C206409aAA2E4a56f9a79c15AB;
    string internal forkUrl = vm.envString("FORK_URL");
    address internal router = vm.envAddress("ROUTER_ADDRESS");
    PortalRegistry internal portalRegistry = PortalRegistry(vm.envAddress("PORTAL_REGISTRY_ADDRESS"));
    SchemaRegistry internal schemaRegistry = SchemaRegistry(vm.envAddress("SCHEMA_REGISTRY_ADDRESS"));
    ModuleRegistry internal moduleRegistry = ModuleRegistry(vm.envAddress("MODULE_REGISTRY_ADDRESS"));
    AttestationRegistry internal attestationRegistry =
        AttestationRegistry(vm.envAddress("ATTESTATION_REGISTRY_ADDRESS"));

    bytes32 internal constant ENCLAVE_IDENTITY_SCHEMA_ID =
        0x97b41ea5b7cea14d9f50d4b8f09b6fff7744522db6e340e18fbc324810ab9152;
    bytes32 internal constant FMSPC_TCB_SCHEMA_ID = 0x46bd450c3c87d1c7842b1efb25c629c61fa188159f1e48326da497f28aef6757;
    bytes32 internal constant PCK_SCHEMA_ID = 0x24c1e0f0784350da3b36c4fc38e701b0218e02a9ec9eba3329d7bcafc339df2b;
    bytes32 internal constant PCS_CERT_SCHEMA_ID = 0xe636510f39fcce1becac6265aeea289429c8ffaa4e37cf7d9a8269f49ab853b6;
    bytes32 internal constant PCS_CRL_SCHEMA_ID = 0xca0446aabb4cf5f2ce35e983f5d0ff69a4cbe43c9740d8e83af54dbc3e4a884c;

    function setUp() public virtual {
        // Fork Linea mainnet
        uint256 fork = vm.createFork(forkUrl);
        vm.selectFork(fork);
        vm.deal(admin, 100 ether);

        // assign issuer role
        vm.prank(registryOwner);
        portalRegistry.setIssuer(admin);

        vm.startPrank(admin);

        // deploy helper libraries
        enclaveIdentityLib = new EnclaveIdentityHelper();
        fsmpcTcbLib = new FmspcTcbHelper();
        x509CrlLib = new X509CRLHelper();
        x509Lib = new X509Helper();

        // registers schemas

        // Enclave Identity Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS Enclave Identity", // name
            "", // Description
            "", // Context
            "uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string identity, bytes signature" // Schema
        );
        // FMSPC TCB Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS FMSPC TCB", // name
            "", // Description
            "", // Context
            "uint256 tcbType, uint256 version, uint256 issueDateTimestamp, uint256 nextUpdateTimestamp, string tcbInfo, bytes signature" // Schema
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
            "bytes pcsCert" // Schema
        );
        // PCS CRL Schema
        schemaRegistry.createSchema(
            "Intel On-Chain PCS Certificate Revocation List", // name
            "", // Description
            "", // Context
            "bytes pcsCrl" // Schema
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
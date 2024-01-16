// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SigVerifyModuleBase} from "./base/SigVerifyModuleBase.sol";
import {
    AbstractModule,
    AttestationPayload
} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractModule.sol";

contract PcsModule is SigVerifyModuleBase, AbstractModule {
    
    bytes32 public constant PCS_CERT_SCHEMA_ID = 0xe636510f39fcce1becac6265aeea289429c8ffaa4e37cf7d9a8269f49ab853b6;
    bytes32 public constant PCS_CRL_SCHEMA_ID = 0xca0446aabb4cf5f2ce35e983f5d0ff69a4cbe43c9740d8e83af54dbc3e4a884c;
    bytes32 public constant CERTIFICATE_CHAIN_SCHEMA_ID = 0x89bd76e17fd84df8e1e448fa1b46dd8d97f7e8e806552b003f8386a5aebcb9f0;

    constructor(address _x509helper) SigVerifyModuleBase(_x509helper) {}

    /// @notice no validation for PCS CA certs since we trust the portal owner to provide legitimate attestations
    function run(
        AttestationPayload memory attestationPayload,
        bytes memory validationPayload,
        address, /* txSender */
        uint256 /* value */
    ) public view override {
        if (attestationPayload.schemaId == PCS_CRL_SCHEMA_ID) {
            // TODO: CRL parser
            bytes memory tbs;
            bytes memory signature;
            bytes32 digest = sha256(tbs);
            
            bool sigVerified = verifySignature(digest, signature, validationPayload);
            if (!sigVerified) {
                revert Invalid_Signature();
            }
        } else if (attestationPayload.schemaId == CERTIFICATE_CHAIN_SCHEMA_ID) {
            (bytes memory cert, bytes memory issuer) = abi.decode(validationPayload, (bytes, bytes));
            (bytes memory tbs, bytes memory signature) = x509Helper.getTbsAndSig(cert);
            bytes32 digest = sha256(tbs);

            bool sigVerified = verifySignature(digest, signature, issuer);
            if (!sigVerified) {
                revert Invalid_Signature();
            }
        }
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SigVerifyModuleBase} from "./base/SigVerifyModuleBase.sol";
import {CA} from "../../Common.sol";
import {X509CRLHelper, X509CRLObj} from "../../helper/X509CRLHelper.sol";

import {
    AbstractModule,
    AttestationPayload
} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractModule.sol";
import {LibString} from "solady/utils/LibString.sol";

contract PcsModule is SigVerifyModuleBase, AbstractModule {
    bytes32 public constant PCS_CERT_SCHEMA_ID = 0xa5dd9ea626846139a00bf8107f573859ba67f5e9a1afd49ed46b68f653276a40;
    bytes32 public constant PCS_CRL_SCHEMA_ID = 0x934a822069030e1200f83fcb82353abee65dde383eab58d55f6833bb084aca78;
    // bytes32 public constant CERTIFICATE_CHAIN_SCHEMA_ID = 0x89bd76e17fd84df8e1e448fa1b46dd8d97f7e8e806552b003f8386a5aebcb9f0;

    // keccak256(hex"0ba9c4c0c0c86193a3fe23d6b02cda10a8bbd4e88e48b4458561a36e705525f567918e2edc88e40d860bd0cc4ee26aacc988e505a953558c453f6b0904ae7394")
    // the uncompressed (0x04) prefix is not included in the pubkey pre-image
    bytes32 public constant ROOT_CA_PUBKEY_HASH = 0x89f72d7c488e5b53a77c23ebcb36970ef7eb5bcf6658e9b8292cfbe4703a8473;

    string public constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string public constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string public constant SIGNING_COMMON_NAME = "Intel SGX TCB Signing";
    string public constant ROOT_CA_COMMON_NAME = "Intel SGX Root CA";

    X509CRLHelper public x509CrlHelper;

    error Unknown_Schema(bytes32 schemaIdFound);
    error Invalid_Issuer_Name();
    error Invalid_Subject_Name();
    error Expired_Certificates();
    error Revoked_Certificate(uint256 serialNumber);
    error Root_Key_Mismatch();

    constructor(address _x509helper, address _x509CrlHelper) SigVerifyModuleBase(_x509helper) {
        x509CrlHelper = X509CRLHelper(_x509CrlHelper);
    }

    /// @notice no validation for PCS CA certs since we trust the portal owner to provide legitimate attestations
    function run(
        AttestationPayload memory attestationPayload,
        bytes memory validationPayload,
        address, /* txSender */
        uint256 /* value */
    ) public view override {
        if (attestationPayload.schemaId == PCS_CRL_SCHEMA_ID) {
            (CA ca, bytes memory encodedCrl) = abi.decode(attestationPayload.attestationData, (CA, bytes));
            {
                bool expired = x509CrlHelper.crlIsNotExpired(encodedCrl);
                if (expired) {
                    revert Expired_Certificates();
                }
            }
            {
                string memory issuerCommonName = x509CrlHelper.getIssuerCommonName(encodedCrl);
                string memory expectedIssuer;
                if (ca == CA.PLATFORM || ca == CA.PROCESSOR) {
                    expectedIssuer = ca == CA.PLATFORM ? PCK_PLATFORM_CA_COMMON_NAME : PCK_PROCESSOR_CA_COMMON_NAME;
                } else {
                    expectedIssuer = ROOT_CA_COMMON_NAME;
                }
                if (!LibString.eq(issuerCommonName, expectedIssuer)) {
                    revert Invalid_Issuer_Name();
                }
            }
            {
                (bytes memory tbs, bytes memory signature) = x509CrlHelper.getTbsAndSig(encodedCrl);
                bytes32 digest = sha256(tbs);
                bool sigVerified = verifySignature(digest, signature, validationPayload);
                if (!sigVerified) {
                    revert Invalid_Signature();
                }
            }
        }
        // else if (attestationPayload.schemaId == CERTIFICATE_CHAIN_SCHEMA_ID) {
        //     (bytes memory cert, bytes memory issuer) = abi.decode(validationPayload, (bytes, bytes));
        //     (bytes memory tbs, bytes memory signature) = x509Helper.getTbsAndSig(cert);
        //     bytes32 digest = sha256(tbs);
        //     bool sigVerified = verifySignature(digest, signature, issuer);
        //     if (!sigVerified) {
        //         revert Invalid_Signature();
        //     }
        // }
        else if (attestationPayload.schemaId == PCS_CERT_SCHEMA_ID) {
            (CA ca, bytes memory cert) = abi.decode(attestationPayload.attestationData, (CA, bytes));
            {
                bool expired = x509Helper.certIsNotExpired(cert);
                if (expired) {
                    revert Expired_Certificates();
                }
            }
            {
                string memory issuerName = x509Helper.getSubjectCommonName(cert);
                string memory subjectName = x509Helper.getSubjectCommonName(cert);
                string memory expectedIssuer = ROOT_CA_COMMON_NAME;
                string memory expectedSubject;
                if (ca == CA.PLATFORM) {
                    expectedSubject = PCK_PLATFORM_CA_COMMON_NAME;
                } else if (ca == CA.PROCESSOR) {
                    expectedSubject = PCK_PROCESSOR_CA_COMMON_NAME;
                } else if (ca == CA.SIGNING) {
                    expectedSubject = SIGNING_COMMON_NAME;
                } else if (ca == CA.ROOT) {
                    expectedSubject = ROOT_CA_COMMON_NAME;
                }
                if (!LibString.eq(issuerName, expectedIssuer)) {
                    revert Invalid_Issuer_Name();
                }
                if (!LibString.eq(subjectName, expectedSubject)) {
                    revert Invalid_Subject_Name();
                }
            }
            {
                if (ca == CA.ROOT) {
                    bytes memory pubKey = x509Helper.getSubjectPublicKey(cert);
                    if (keccak256(pubKey) != ROOT_CA_PUBKEY_HASH) {
                        revert Root_Key_Mismatch();
                    }
                }
                (bytes memory tbs, bytes memory signature) = x509Helper.getTbsAndSig(cert);
                bytes32 digest = sha256(tbs);
                bool sigVerified = verifySignature(digest, signature, validationPayload);
                if (!sigVerified) {
                    revert Invalid_Signature();
                }
            }
        } else {
            revert Unknown_Schema(attestationPayload.schemaId);
        }
    }
}

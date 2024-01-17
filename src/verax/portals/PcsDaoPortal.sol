// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {LibString} from "solady/utils/LibString.sol";
import {PcsDao, AttestationRequest, CA} from "../../dao/PcsDao.sol";
import {X509CRLHelper} from "../../helper/X509CRLHelper.sol";
import {SigVerifyModuleBase} from "../base/SigVerifyModuleBase.sol";

contract PcsDaoPortal is PcsDao, AbstractPortal, SigVerifyModuleBase {
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);

    error Certificate_Revoked(CA ca, uint256 serialNum);
    error Invalid_Issuer_Name();
    error Invalid_Subject_Name();
    error Expired_Certificates();
    error Root_Key_Mismatch();
    error Revocation_Forbidden();

    string constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string constant SIGNING_COMMON_NAME = "Intel SGX TCB Signing";
    string constant ROOT_CA_COMMON_NAME = "Intel SGX Root CA";

    // keccak256(hex"0ba9c4c0c0c86193a3fe23d6b02cda10a8bbd4e88e48b4458561a36e705525f567918e2edc88e40d860bd0cc4ee26aacc988e505a953558c453f6b0904ae7394")
    // the uncompressed (0x04) prefix is not included in the pubkey pre-image
    bytes32 constant ROOT_CA_PUBKEY_HASH = 0x89f72d7c488e5b53a77c23ebcb36970ef7eb5bcf6658e9b8292cfbe4703a8473;

    bool private _unlock;
    X509CRLHelper public x509CrlHelper;

    constructor(address[] memory modules, address router, address x509, address x509Crl)
        AbstractPortal(modules, router)
        SigVerifyModuleBase(x509)
    {
        // validation is done here. No need for a module.
        require(modules.length == 0);
        x509CrlHelper = X509CRLHelper(x509Crl);
    }

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function pcsCertSchemaID() public pure override returns (bytes32 PCS_CERT_SCHEMA_ID) {
        // keccak256(bytes("bytes pcsCert"))
        PCS_CERT_SCHEMA_ID = 0xe636510f39fcce1becac6265aeea289429c8ffaa4e37cf7d9a8269f49ab853b6;
    }

    function pcsCrlSchemaID() public pure override returns (bytes32 PCS_CRL_SCHEMA_ID) {
        // keccak256(bytes("bytes pcsCrl"))
        PCS_CRL_SCHEMA_ID = 0xca0446aabb4cf5f2ce35e983f5d0ff69a4cbe43c9740d8e83af54dbc3e4a884c;
    }

    // function certificateChainSchemaID() public pure override returns (bytes32 CERTIFICATE_CHAIN_SCHEMA_ID) {
    //     // https://docs.ver.ax/verax-documentation/developer-guides/for-attestation-issuers/link-attestations
    //     CERTIFICATE_CHAIN_SCHEMA_ID = 0x89bd76e17fd84df8e1e448fa1b46dd8d97f7e8e806552b003f8386a5aebcb9f0;
    // }

    function _attestPcs(AttestationRequest memory req, CA ca) internal override returns (bytes32 attestationId) {
        _unlock = true;

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, ca);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
        attestationId = bytes32(abi.encode(attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        bytes[] memory empty = new bytes[](0);
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

    // function _attestCertChain(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
    //     _unlock = true;

    //     bytes[] memory validationPayload = new bytes[](1);

    //     (bytes32 certAttestationId,, bytes32 issuerAttestationId) =
    //         abi.decode(req.data.data, (bytes32, string, bytes32));

    //     bytes memory cert = _getAttestedData(certAttestationId);
    //     bytes memory issuer = _getAttestedData(issuerAttestationId);
    //     validationPayload[0] = abi.encode(cert, issuer);

    //     AttestationPayload memory attestationPayload =
    //         AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

    //     uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
    //     attestationId = bytes32(abi.encode(attestationIdCounter));

    //     super.attest(attestationPayload, validationPayload);

    //     _unlock = false;
    // }

    function _getAttestedData(bytes32 attestationId) internal view override returns (bytes memory attestationData) {
        Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
        if (attestation.revoked) {
            revert Attestation_Revoked(attestationId, attestation.replacedBy);
        }
        attestationData = attestation.attestationData;
    }

    function _onRevoke(bytes32 attestationId) internal view override {
        Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
        bytes memory cert = attestation.attestationData;
        bytes memory rootCrl = _getAttestedData(pcsCrlAttestations[CA.ROOT]);
        CA ca;
        string memory subjectCommonName = x509Helper.getSubjectCommonName(cert);
        if (LibString.eq(subjectCommonName, PCK_PLATFORM_CA_COMMON_NAME)) {
            ca = CA.PLATFORM;
        } else if (LibString.eq(subjectCommonName, PCK_PROCESSOR_CA_COMMON_NAME)) {
            ca = CA.PROCESSOR;
        } else {
            revert Invalid_Subject_Name();
        }
        bytes32 schemaId = attestation.schemaId;
        if (schemaId == pcsCertSchemaID() && (ca == CA.PROCESSOR || ca == CA.PLATFORM) && rootCrl.length > 0) {
            uint256 serialNum = x509Helper.getSerialNumber(cert);
            bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, rootCrl);
            if (!revoked) {
                revert Revocation_Forbidden();
            }
        } else {
            revert Revocation_Forbidden();
        }
    }

    function _onBulkRevoke(bytes32[] memory attestationIds) internal view override {
        for (uint256 i = 0; i < attestationIds.length; i++) {
            _onRevoke(attestationIds[i]);
        }
    }

    function _onAttest(AttestationPayload memory attestationPayload, address, /*attester*/ uint256 /*value*/ )
        internal
        override
        locked
    {
        // Do nothing
    }

    function _onBulkAttest(
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    function _onReplace(
        bytes32, /*attestationId*/
        AttestationPayload memory, /*attestationPayload*/
        address, /*attester*/
        uint256 /*value*/
    ) internal override locked {
        // Do nothing
    }

    function _onBulkReplace(
        bytes32[] memory, /*attestationIds*/
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {
        /// @notice: external attestations not possible, therefore this code is unreachable
    }

    function _getIssuer(CA ca) private view returns (bytes memory issuerCert) {
        bytes32 intermediateCertAttestationId = pcsCertAttestations[ca];
        bytes32 rootCertAttestationId = pcsCertAttestations[CA.ROOT];
        if (ca != CA.ROOT) {
            // if (!verifyCertchain(intermediateCertAttestationId, rootCertAttestationId)) {
            //     revert("Unverified CRL Cert Chain");
            // }
            issuerCert = _getAttestedData(intermediateCertAttestationId);
        } else {
            issuerCert = _getAttestedData(rootCertAttestationId);
        }
    }

    function _validate(AttestationPayload memory attestationPayload, CA ca) private view {
        if (attestationPayload.schemaId == pcsCrlSchemaID()) {
            bytes memory encodedCrl = attestationPayload.attestationData;
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
                bool sigVerified = verifySignature(digest, signature, _getIssuer(ca));
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
        else if (attestationPayload.schemaId == pcsCertSchemaID()) {
            bytes memory cert = attestationPayload.attestationData;
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
            bytes memory issuerCert = _getIssuer(CA.ROOT);
            bytes memory rootCrl = _getAttestedData(pcsCrlAttestations[CA.ROOT]);
            {
                if (ca == CA.ROOT) {
                    bytes memory pubKey = x509Helper.getSubjectPublicKey(cert);
                    if (keccak256(pubKey) != ROOT_CA_PUBKEY_HASH) {
                        revert Root_Key_Mismatch();
                    }
                } else if ((ca == CA.PROCESSOR || ca == CA.PLATFORM) && rootCrl.length > 0) {
                    uint256 serialNum = x509Helper.getSerialNumber(cert);
                    bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, rootCrl);
                    if (revoked) {
                        revert Certificate_Revoked(ca, serialNum);
                    }
                }
                (bytes memory tbs, bytes memory signature) = x509Helper.getTbsAndSig(cert);
                bytes32 digest = sha256(tbs);
                bool sigVerified = verifySignature(digest, signature, issuerCert);
                if (!sigVerified) {
                    revert Invalid_Signature();
                }
            }
        }
    }
}

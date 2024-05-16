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
    error Forbidden();

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

    function getAttestedData(bytes32 attestationId, bool hashOnly)
        public
        view
        override
        returns (bytes memory attestationData)
    {
        if (attestationRegistry.isRegistered(attestationId)) {
            Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
            if (attestation.revoked) {
                revert Attestation_Revoked(attestationId, attestation.replacedBy);
            }
            attestationData = attestation.attestationData;
        }
    }

    function pcsCertSchemaID() public pure override returns (bytes32 PCS_CERT_SCHEMA_ID) {
        // keccak256(bytes("bytes32 identifier, bytes pcsCert"))
        PCS_CERT_SCHEMA_ID = 0xedc3e4f5846d93e65599fb22bc868cdb3ec6c766bbe6145acb2c3ab4765e0eb0;
    }

    function pcsCrlSchemaID() public pure override returns (bytes32 PCS_CRL_SCHEMA_ID) {
        // keccak256(bytes("bytes32 identifier, bytes pcsCrl"))
        PCS_CRL_SCHEMA_ID = 0x420573d190f658fca27d49a4c5568195f63283301f2fd65104f7704e9442b912;
    }

    function _attestPcs(AttestationRequest memory req, CA ca) internal override returns (bytes32 attestationId) {
        _unlock = true;

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, ca);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter() + 1;
        uint256 chainPrefix = attestationRegistry.getChainPrefix();
        attestationId = bytes32(abi.encode(chainPrefix + attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        bytes[] memory empty = new bytes[](0);

        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

    function _getTbsIdentifier(bool isCrl, bytes memory der) internal view override returns (bytes32 id) {
        bytes memory tbs;
        if (isCrl) {
            (tbs,) = x509CrlHelper.getTbsAndSig(der);
        } else {
            (tbs,) = x509Helper.getTbsAndSig(der);
        }
        id = keccak256(tbs);
    }

    function _onRevoke(bytes32 attestationId) internal view override {
        Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
        bytes memory cert = attestation.attestationData;
        bytes memory rootCrl = getAttestedData(pcsCrlAttestations[CA.ROOT], false);
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
                revert Forbidden();
            }
        } else {
            revert Forbidden();
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
        bytes memory data;
        if (ca != CA.ROOT) {
            data = getAttestedData(intermediateCertAttestationId, false);
        } else {
            data = getAttestedData(rootCertAttestationId, false);
        }
        if (data.length > 0) {
            (, issuerCert) = abi.decode(data, (bytes32, bytes));
        }
    }

    function _validate(AttestationPayload memory attestationPayload, CA ca) private view {
        if (attestationPayload.schemaId == pcsCrlSchemaID()) {
            (, bytes memory encodedCrl) = abi.decode(attestationPayload.attestationData, (bytes32, bytes));
            {
                bool valid = x509CrlHelper.crlIsNotExpired(encodedCrl);
                if (!valid) {
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
        } else if (attestationPayload.schemaId == pcsCertSchemaID()) {
            (, bytes memory cert) = abi.decode(attestationPayload.attestationData, (bytes32, bytes));
            {
                bool valid = x509Helper.certIsNotExpired(cert);
                if (!valid) {
                    revert Expired_Certificates();
                }
            }
            {
                string memory issuerName = x509Helper.getIssuerCommonName(cert);
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
            bytes memory rootCrlData = getAttestedData(pcsCrlAttestations[CA.ROOT], false);
            {
                if (ca == CA.ROOT) {
                    bytes memory pubKey = x509Helper.getSubjectPublicKey(cert);
                    if (keccak256(pubKey) != ROOT_CA_PUBKEY_HASH) {
                        revert Root_Key_Mismatch();
                    }
                } else if ((ca == CA.PROCESSOR || ca == CA.PLATFORM) && rootCrlData.length > 0) {
                    uint256 serialNum = x509Helper.getSerialNumber(cert);
                    (, bytes memory rootCrl) = abi.decode(rootCrlData, (bytes32, bytes));
                    bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, rootCrl);
                    if (revoked) {
                        revert Certificate_Revoked(ca, serialNum);
                    }
                }

                if (issuerCert.length > 0) {
                    (bytes memory tbs, bytes memory signature) = x509Helper.getTbsAndSig(cert);
                    bytes32 digest = sha256(tbs);
                    bool sigVerified = verifySignature(digest, signature, issuerCert);
                    if (!sigVerified) {
                        revert Invalid_Signature();
                    }
                } else if (ca != CA.ROOT) {
                    // all other certificates should already have an iusuer configured
                    revert Forbidden();
                }
            }
        }
    }
}

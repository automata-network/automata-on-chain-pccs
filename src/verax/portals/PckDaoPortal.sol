// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {LibString} from "solady/utils/LibString.sol";
import {PckDao, AttestationRequest, CA} from "../../dao/PckDao.sol";
import {X509CRLHelper} from "../../helper/X509CRLHelper.sol";
import {SigVerifyModuleBase} from "../base/SigVerifyModuleBase.sol";

contract PckDaoPortal is PckDao, AbstractPortal, SigVerifyModuleBase {
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);

    error Certificate_Revoked(uint256 serialNum);
    error Invalid_Issuer_Name();
    error Invalid_Subject_Name();
    error Expired_Certificates();
    error Revocation_Forbidden();

    string constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string constant PCK_COMMON_NAME = "Intel SGX PCK Certificate";

    bool private _unlock;
    X509CRLHelper public x509CrlHelper;

    constructor(address[] memory modules, address router, address pcs, address x509, address x509crl)
        AbstractPortal(modules, router)
        PckDao(pcs)
        SigVerifyModuleBase(x509)
    {
        // validation is done here. No need for a module.
        require(modules.length == 0);
        x509CrlHelper = X509CRLHelper(x509crl);
    }

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function pckSchemaID() public pure override returns (bytes32 PCK_SCHEMA_ID) {
        // keccak256(bytes("bytes pckCert"))
        PCK_SCHEMA_ID = 0x24c1e0f0784350da3b36c4fc38e701b0218e02a9ec9eba3329d7bcafc339df2b;
    }

    function _attestPck(AttestationRequest memory req, CA ca) internal override returns (bytes32 attestationId) {
        _unlock = true;

        bytes[] memory empty = new bytes[](0);

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, ca);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
        attestationId = bytes32(abi.encode(attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

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
        CA ca;
        string memory issuerName = x509Helper.getIssuerCommonName(cert);
        if (LibString.eq(issuerName, PCK_PLATFORM_CA_COMMON_NAME)) {
            ca = CA.PLATFORM;
        } else if (LibString.eq(issuerName, PCK_PROCESSOR_CA_COMMON_NAME)) {
            ca = CA.PROCESSOR;
        } else {
            revert Invalid_Issuer_Name();
        }
        bytes memory crl = _getAttestedData(Pcs.pcsCrlAttestations(ca));
        if (crl.length > 0) {
            uint256 serialNum = x509Helper.getSerialNumber(cert);
            bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, crl);
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

    function _onAttest(AttestationPayload memory, /*attestationPayload*/ address, /*attester*/ uint256 /*value*/ )
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

    function _validate(AttestationPayload memory attestationPayload, CA ca) private view {
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
            string memory expectedIssuer;
            if (ca == CA.PLATFORM) {
                expectedIssuer = PCK_PLATFORM_CA_COMMON_NAME;
            } else if (ca == CA.PROCESSOR) {
                expectedIssuer = PCK_PROCESSOR_CA_COMMON_NAME;
            }
            if (!LibString.eq(issuerName, expectedIssuer)) {
                revert Invalid_Issuer_Name();
            }
            if (!LibString.eq(subjectName, PCK_COMMON_NAME)) {
                revert Invalid_Subject_Name();
            }
        }
        (bytes memory issuerCert,) = getPckCertChain(ca);
        bytes memory crl = _getAttestedData(Pcs.pcsCrlAttestations(ca));
        {
            if (crl.length > 0) {
                uint256 serialNum = x509Helper.getSerialNumber(cert);
                bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, crl);
                if (revoked) {
                    revert Certificate_Revoked(serialNum);
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

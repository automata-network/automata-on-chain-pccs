// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {LibString} from "solady/utils/LibString.sol";
import {PckDao, AttestationRequest, CA} from "../../dao/PckDao.sol";
import {X509CRLHelper} from "../../helper/X509CRLHelper.sol";
import {PCKHelper, X509CertObj} from "../../helper/PCKHelper.sol";
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
    error TCB_Mismatch();
    error Forbidden();

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

    function tcbmSchemaId() public pure override returns (bytes32 TCBM_SCHEMA_ID) {
        // keccak256(bytes("string tcbm"))
        TCBM_SCHEMA_ID = 0x66d92880cb1d562dbbaf8430efd3eee3280bea1319ae21e4ebb4cd7f73134342;
    }

    function _attestPck(AttestationRequest memory req, CA ca, string calldata pceid, string calldata tcbm)
        internal
        override
        returns (bytes32 attestationId)
    {
        _unlock = true;

        bytes[] memory empty = new bytes[](0);

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        _validate(attestationPayload, ca, pceid, tcbm);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter() + 1;
        uint256 chainPrefix = attestationRegistry.getChainPrefix();
        attestationId = bytes32(abi.encode(chainPrefix + attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

    function _attestTcbm(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
        _unlock = true;

        bytes[] memory empty = new bytes[](0);

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter() + 1;
        uint256 chainPrefix = attestationRegistry.getChainPrefix();
        attestationId = bytes32(abi.encode(chainPrefix + attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, empty);
        } else {
            super.replace(predecessor, attestationPayload, empty);
        }

        _unlock = false;
    }

    function _getAttestedData(bytes32 attestationId) internal view override returns (bytes memory attestationData) {
        if (attestationRegistry.isRegistered(attestationId)) {
            Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
            if (attestation.revoked) {
                revert Attestation_Revoked(attestationId, attestation.replacedBy);
            }
            attestationData = attestation.attestationData;
        }
    }

    function _onRevoke(bytes32 attestationId) internal view override {
        Attestation memory attestation = attestationRegistry.getAttestation(attestationId);
        if (attestation.schemaId == pckSchemaID()) {
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
                    revert Forbidden();
                }
            } else {
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

    function _validate(AttestationPayload memory attestationPayload, CA ca, string calldata pceid, string calldata tcbm)
        private
        view
    {
        bytes memory cert = attestationPayload.attestationData;
        {
            // check certificate validity
            bool valid = x509Helper.certIsNotExpired(cert);
            if (!valid) {
                revert Expired_Certificates();
            }
        }
        X509CertObj memory pck;
        {
            // check certificate issuer and subject names
            pck = x509Helper.parseX509DER(cert);
            string memory expectedIssuer;
            if (ca == CA.PLATFORM) {
                expectedIssuer = PCK_PLATFORM_CA_COMMON_NAME;
            } else if (ca == CA.PROCESSOR) {
                expectedIssuer = PCK_PROCESSOR_CA_COMMON_NAME;
            }
            if (!LibString.eq(pck.issuerCommonName, expectedIssuer)) {
                revert Invalid_Issuer_Name();
            }
            if (!LibString.eq(pck.subjectCommonName, PCK_COMMON_NAME)) {
                revert Invalid_Subject_Name();
            }
        }
        {
            // validate pceid and tcbm
            (uint16 pcesvn, uint8[] memory cpusvns,, bytes memory pceidBytes) =
                PCKHelper(address(x509Helper)).parsePckExtension(cert, pck.extensionPtr);
            bool pceidMatched = LibString.eq(pceid, LibString.toHexStringNoPrefix(pceidBytes));
            bool tcbIsValid = _validateTcb(tcbm, pcesvn, cpusvns);
            if (!pceidMatched || !tcbIsValid) {
                revert TCB_Mismatch();
            }
        }
        (bytes memory issuerCert,) = getPckCertChain(ca);
        bytes memory crlData = _getAttestedData(Pcs.pcsCrlAttestations(ca));
        {
            // check whether certificate has been revoked and signed by a valid CA
            if (crlData.length > 0) {
                (,bytes memory crl) = abi.decode(crlData, (bytes32, bytes));
                uint256 serialNum = pck.serialNumber;
                bool revoked = x509CrlHelper.serialNumberIsRevoked(serialNum, crl);
                if (revoked) {
                    revert Certificate_Revoked(serialNum);
                }
            }
            if (issuerCert.length > 0) {
                bytes32 digest = sha256(pck.tbs);
                bool sigVerified = verifySignature(digest, pck.signature, issuerCert);
                if (!sigVerified) {
                    revert Invalid_Signature();
                }
            } else {
                revert Forbidden();
            }
        }
    }

    function _validateTcb(string memory tcbm, uint16 pcesvn, uint8[] memory cpusvns) private pure returns (bool) {
        bytes memory encodedPceSvn = _littleEndianEncode(abi.encodePacked(pcesvn));
        bytes memory encodedCpuSvn;
        for (uint256 i = 0; i < cpusvns.length; i++) {
            encodedCpuSvn = abi.encodePacked(encodedCpuSvn, cpusvns[i]);
        }
        bytes memory encodedTcbmBytes = abi.encodePacked(encodedCpuSvn, encodedPceSvn);
        string memory encodedTcbmHex = LibString.toHexStringNoPrefix(encodedTcbmBytes);
        return LibString.eq(tcbm, encodedTcbmHex);
    }

    function _littleEndianEncode(bytes memory input) private pure returns (bytes memory encoded) {
        uint256 n = input.length;
        for (uint256 i = n; i > 0;) {
            encoded = abi.encodePacked(encoded, input[i - 1]);
            unchecked {
                i--;
            }
        }
    }
}

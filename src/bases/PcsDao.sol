// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {X509Helper, X509CertObj} from "../helpers/X509Helper.sol";
import {X509CRLHelper, X509CRLObj} from "../helpers/X509CRLHelper.sol";

import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

import {LibString} from "solady/utils/LibString.sol";

/**
 * @title Intel PCS Data Access Object
 * @notice This is a core contract of our on-chain PCCS implementation as it provides methods
 * @notice to read/write essential collaterals such as the RootCA, Intermediate CAs and CRLs.
 * @notice All other DAOs are expected to configure and make external calls to this contract to fetch those collaterals.
 * @notice This contract is heavily inspired by Sections 4.2.5 and 4.2.6 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 */
abstract contract PcsDao is DaoBase, SigVerifyBase {
    using LibString for string;

    X509CRLHelper public crlLib;

    /// @notice Fetches the attestationId of the attested PCS Certificate
    ///
    /// @dev Must ensure that the public key for the configured Intel Root CA matches with
    /// @dev the Intel source code at: https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QvE/Enclave/qve.cpp#L92-L100
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pcsCert
    mapping(CA => bytes32) public pcsCertAttestations;

    /// @notice Fetches the attestationId of the attested PCS CRLs
    ///
    /// @dev Verification of CRLs are conducted as part of the PCS attestation process
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pcsCrl
    mapping(CA => bytes32) public pcsCrlAttestations;

    string constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string constant SIGNING_COMMON_NAME = "Intel SGX TCB Signing";
    string constant ROOT_CA_COMMON_NAME = "Intel SGX Root CA";

    // keccak256(hex"0ba9c4c0c0c86193a3fe23d6b02cda10a8bbd4e88e48b4458561a36e705525f567918e2edc88e40d860bd0cc4ee26aacc988e505a953558c453f6b0904ae7394")
    // the uncompressed (0x04) prefix is not included in the pubkey pre-image
    bytes32 constant ROOT_CA_PUBKEY_HASH = 0x89f72d7c488e5b53a77c23ebcb36970ef7eb5bcf6658e9b8292cfbe4703a8473;

    error Missing_Certificate(CA ca);
    error Invalid_PCK_CA(CA ca);
    error Invalid_Issuer_Name();
    error Invalid_Subject_Name();
    error Certificate_Expired();
    error Root_Key_Mismatch();
    error Certificate_Revoked(CA ca, uint256 serialNum);
    error Missing_Issuer();
    error Invalid_Signature();

    constructor(address _x509, address _crl) SigVerifyBase(_x509) {
        crlLib = X509CRLHelper(_crl);
    }

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert Invalid_PCK_CA(ca);
        }
        _;
    }

    /**
     * @param ca see {Common.sol} for definition
     * @return cert - DER encoded certificate
     * @return crl - DER-encoded CRLs that is signed by the provided cert
     */
    function getCertificateById(CA ca) external view returns (bytes memory cert, bytes memory crl) {
        bytes32 pcsCertAttestationId = pcsCertAttestations[ca];
        if (pcsCertAttestationId == bytes32(0)) {
            revert Missing_Certificate(ca);
        }
        cert = getAttestedData(pcsCertAttestationId);

        bytes32 pcsCrlAttestationId = pcsCrlAttestations[ca];
        if (pcsCrlAttestationId != bytes32(0)) {
            crl = getAttestedData(pcsCrlAttestationId);
        }
    }

    /**
     * Section 4.2.6 (upsertPcsCertificates)
     * @param ca replaces the "id" value with the ca_id
     * @param cert the DER-encoded certificate
     */
    function upsertPcsCertificates(CA ca, bytes calldata cert) external returns (bytes32 attestationId) {
        bytes32 hash = _validatePcsCert(ca, cert);
        AttestationRequest memory req = _buildPcsAttestationRequest(false, ca, cert);
        attestationId = _attestPcs(req, hash);
        pcsCertAttestations[ca] = attestationId;
    }

    /**
     * Section 4.2.5 (upsertPckCrl)
     * @param ca either CA.PROCESSOR or CA.PLATFORM
     * @param crl the DER-encoded CRL
     */
    function upsertPckCrl(CA ca, bytes calldata crl) external pckCACheck(ca) returns (bytes32 attestationId) {
        attestationId = _upsertPcsCrl(ca, crl);
    }

    function upsertRootCACrl(bytes calldata rootcacrl) external returns (bytes32 attestationId) {
        attestationId = _upsertPcsCrl(CA.ROOT, rootcacrl);
    }

    function pcsCertSchemaID() public view virtual returns (bytes32 PCS_CERT_SCHEMA_ID);

    function pcsCrlSchemaID() public view virtual returns (bytes32 PCS_CRL_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest PCS Certificates or CRLs
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestPcs(AttestationRequest memory req, bytes32 hash) internal virtual returns (bytes32 attestationId);

    function _upsertPcsCrl(CA ca, bytes calldata crl) private returns (bytes32 attestationId) {
        bytes32 hash = _validatePcsCrl(ca, crl);
        AttestationRequest memory req = _buildPcsAttestationRequest(true, ca, crl);
        attestationId = _attestPcs(req, hash);
        pcsCrlAttestations[ca] = attestationId;
    }

    /**
     * @notice builds an EAS compliant attestation request
     * @param isCrl - true only if the attested data is a CRL
     * @param der - contains the DER encoded data, specified by isCrl and CA
     */
    function _buildPcsAttestationRequest(bool isCrl, CA ca, bytes calldata der)
        private
        view
        returns (AttestationRequest memory req)
    {
        bytes32 predecessorAttestationId = isCrl ? pcsCrlAttestations[ca] : pcsCertAttestations[ca];
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0, // assign zero here because this has already been checked
            revocable: true,
            refUID: predecessorAttestationId,
            data: der,
            value: 0
        });
        bytes32 schemaId = isCrl ? pcsCrlSchemaID() : pcsCertSchemaID();
        req = AttestationRequest({schema: schemaId, data: reqData});
    }

    function _validatePcsCert(CA ca, bytes calldata cert) private view returns (bytes32 hash) {
        X509Helper x509Lib = X509Helper(x509);

        // Step 1: Check whether cert has expired
        bool notExpired = x509Lib.certIsNotExpired(cert);
        if (!notExpired) {
            revert Certificate_Expired();
        }

        // Step 2: Check issuer and subject common names are valid
        string memory issuerName = x509Lib.getIssuerCommonName(cert);
        string memory subjectName = x509Lib.getSubjectCommonName(cert);
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

        // Step 3: Check Revocation Status
        bytes memory rootCrlData = getAttestedData(pcsCrlAttestations[CA.ROOT]);
        if (ca == CA.ROOT) {
            bytes memory pubKey = x509Lib.getSubjectPublicKey(cert);
            if (keccak256(pubKey) != ROOT_CA_PUBKEY_HASH) {
                revert Root_Key_Mismatch();
            }
        } else if (rootCrlData.length > 0) {
            uint256 serialNum = x509Lib.getSerialNumber(cert);
            bool revoked = crlLib.serialNumberIsRevoked(serialNum, rootCrlData);
            if (revoked) {
                revert Certificate_Revoked(ca, serialNum);
            }
        }

        // Step 4: Check signature
        bytes memory rootCert = _getIssuer(CA.ROOT);
        (bytes memory tbs, bytes memory signature) = x509Lib.getTbsAndSig(cert);
        bytes32 digest = sha256(tbs);
        bool sigVerified;
        if (ca == CA.ROOT) {
            // the root certificate is issued by its own key
            sigVerified = verifySignature(digest, signature, cert);
        } else if (rootCert.length > 0) {
            sigVerified = verifySignature(digest, signature, rootCert);
        } else {
            // all other certificates should already have an iusuer configured
            revert Missing_Issuer();
        }

        if (!sigVerified) {
            revert Invalid_Signature();
        }

        hash = keccak256(tbs);
    }

    function _validatePcsCrl(CA ca, bytes calldata crl) private view returns (bytes32 hash) {
        // Step 1: Check whether CRL has expired
        bool notExpired = crlLib.crlIsNotExpired(crl);
        if (!notExpired) {
            revert Certificate_Expired();
        }

        // Step 2: Check CRL issuer
        string memory issuerCommonName = crlLib.getIssuerCommonName(crl);
        string memory expectedIssuer;
        if (ca == CA.PLATFORM || ca == CA.PROCESSOR) {
            expectedIssuer = ca == CA.PLATFORM ? PCK_PLATFORM_CA_COMMON_NAME : PCK_PROCESSOR_CA_COMMON_NAME;
        } else {
            expectedIssuer = ROOT_CA_COMMON_NAME;
        }
        if (!LibString.eq(issuerCommonName, expectedIssuer)) {
            revert Invalid_Issuer_Name();
        }

        // Step 3: Verify signature
        (bytes memory tbs, bytes memory signature) = crlLib.getTbsAndSig(crl);
        bytes32 digest = sha256(tbs);
        bool sigVerified = verifySignature(digest, signature, _getIssuer(ca));
        if (!sigVerified) {
            revert Invalid_Signature();
        }

        hash = keccak256(tbs);
    }

    function _getIssuer(CA ca) private view returns (bytes memory issuerCert) {
        bytes32 intermediateCertAttestationId = pcsCertAttestations[ca];
        bytes32 rootCertAttestationId = pcsCertAttestations[CA.ROOT];
        if (ca == CA.PLATFORM || ca == CA.PROCESSOR) {
            // this is applicable to crls only
            // since all certs in the pcsdao are issued by the root
            issuerCert = getAttestedData(intermediateCertAttestationId);
        } else {
            issuerCert = getAttestedData(rootCertAttestationId);
        }
    }
}

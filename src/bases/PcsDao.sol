// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA} from "../Common.sol";
import {X509Helper, X509CertObj} from "../helpers/X509Helper.sol";
import {X509CRLHelper, X509CRLObj} from "../helpers/X509CRLHelper.sol";

import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

import {LibString} from "solady/utils/LibString.sol";

/// @notice the schema of the attested data for PCS Certs is simply DER-encoded form of the X509
/// @notice Certificate stored in bytes

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

    string constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string constant SIGNING_COMMON_NAME = "Intel SGX TCB Signing";
    string constant ROOT_CA_COMMON_NAME = "Intel SGX Root CA";

    /// keccak256(hex"0ba9c4c0c0c86193a3fe23d6b02cda10a8bbd4e88e48b4458561a36e705525f567918e2edc88e40d860bd0cc4ee26aacc988e505a953558c453f6b0904ae7394")
    /// the uncompressed (0x04) prefix is not included in the pubkey pre-image
    /// @dev Must ensure that the public key for the configured Intel Root CA matches with
    /// @dev the Intel source code at: https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QvE/Enclave/qve.cpp#L92-L100
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

    constructor(address _resolver, address _p256, address _x509, address _crl)
        SigVerifyBase(_p256, _x509)
        DaoBase(_resolver)
    {
        crlLib = X509CRLHelper(_crl);
    }

    function PCS_KEY(CA ca, bool isCrl) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(uint8(ca), isCrl));
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
        cert = getAttestedData(PCS_KEY(ca, false));

        if (cert.length == 0) {
            revert Missing_Certificate(ca);
        }

        crl = getAttestedData(PCS_KEY(ca, true));
    }

    /**
     * Section 4.2.6 (upsertPcsCertificates)
     * @param ca replaces the "id" value with the ca_id
     * @param cert the DER-encoded certificate
     */
    function upsertPcsCertificates(CA ca, bytes calldata cert) external returns (bytes32 attestationId) {
        bytes32 hash = _validatePcsCert(ca, cert);
        bytes32 key = PCS_KEY(ca, false);
        attestationId = _attestPcs(cert, hash, key);
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

    /**
     * @dev implement logic to validate and attest PCS Certificates or CRLs
     * @return attestationId
     */
    function _attestPcs(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        virtual
        returns (bytes32 attestationId)
    {
        (attestationId,) = resolver.attest(key, reqData, hash);
    }

    function _upsertPcsCrl(CA ca, bytes calldata crl) private returns (bytes32 attestationId) {
        bytes32 hash = _validatePcsCrl(ca, crl);
        bytes32 key = PCS_KEY(ca, true);
        attestationId = _attestPcs(crl, hash, key);
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
        bytes memory rootCrlData = getAttestedData(PCS_KEY(CA.ROOT, true));
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
        if (ca == CA.PLATFORM || ca == CA.PROCESSOR) {
            // this is applicable to crls only
            // since all certs in the pcsdao are issued by the root
            issuerCert = getAttestedData(PCS_KEY(ca, false));
        } else {
            issuerCert = getAttestedData(PCS_KEY(CA.ROOT, false));
        }
    }
}

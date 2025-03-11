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
 * @notice This is the core contract of our on-chain PCCS implementation as it provides methods
 * @notice to read/write essential collaterals such as the RootCA, Intermediate CAs and CRLs.
 * @notice All other DAOs are expected to make external calls to this contract to fetch those collaterals.
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

    // first 4 bytes of keccak256('PCS_MAGIC')
    bytes4 constant PCS_MAGIC = 0xe90e3dc7;

    /// keccak256(hex"0ba9c4c0c0c86193a3fe23d6b02cda10a8bbd4e88e48b4458561a36e705525f567918e2edc88e40d860bd0cc4ee26aacc988e505a953558c453f6b0904ae7394")
    /// the uncompressed (0x04) prefix is not included in the pubkey pre-image
    /// @dev Must ensure that the public key for the configured Intel Root CA matches with
    /// @dev the Intel source code at: https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QvE/Enclave/qve.cpp#L92-L100
    bytes32 constant ROOT_CA_PUBKEY_HASH = 0x89f72d7c488e5b53a77c23ebcb36970ef7eb5bcf6658e9b8292cfbe4703a8473;

    // 33247a8a
    error Missing_Certificate(CA ca);
    // 9849e774
    error Invalid_PCK_CA(CA ca);
    // e1406f79
    error Root_Key_Mismatch();
    // 291990cd
    error Certificate_Revoked(CA ca, uint256 serialNum);
    // 5f066611
    error Certificate_Expired(CA ca);
    // 6d8932ad
    error Crl_Expired(CA ca);
    // 1e7ab599
    error Invalid_Issuer_Name();
    // 92ec707e
    error Invalid_Subject_Name();
    // e6612a12
    error Expired_Certificates();
    // 4a629e24
    error TCB_Mismatch();
    // cd69d374
    error Missing_Issuer();
    // e7ef341f
    error Invalid_Signature();
    // 9f4daa9e
    error Certificate_Out_Of_Date();

    event UpsertedPCSCollateral(CA indexed ca, bool isCrl);

    constructor(address _resolver, address _p256, address _x509, address _crl)
        SigVerifyBase(_p256, _x509)
        DaoBase(_resolver)
    {
        crlLib = X509CRLHelper(_crl);
    }

    function getCollateralValidity(bytes32 key)
        external
        view
        override
        returns (uint64 notValidBefore, uint64 notValidAfter)
    {
        (notValidBefore, notValidAfter) = _loadPcsValidity(key);
    }

    function PCS_KEY(CA ca, bool isCrl) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(PCS_MAGIC, uint8(ca), isCrl));
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
        cert = _onFetchDataFromResolver(PCS_KEY(ca, false), false);

        if (cert.length == 0) {
            revert Missing_Certificate(ca);
        }

        crl = _onFetchDataFromResolver(PCS_KEY(ca, true), false);
    }

    /**
     * Section 4.2.6 (upsertPcsCertificates)
     * @param ca replaces the "id" value with the ca_id
     * @param cert the DER-encoded certificate
     */
    function upsertPcsCertificates(CA ca, bytes calldata cert) external returns (bytes32 attestationId) {
        (bytes32 hash, bytes32 key, X509CertObj memory parsedX509Cert) = _validatePcsCert(ca, cert);

        // attest validity
        _storePcsValidity(key, uint64(parsedX509Cert.validityNotBefore), uint64(parsedX509Cert.validityNotAfter));

        attestationId = _attestPcs(cert, hash, key);

        emit UpsertedPCSCollateral(ca, false);
    }

    /**
     * Section 4.2.5 (upsertPckCrl)
     * @param ca either CA.PROCESSOR or CA.PLATFORM
     * @param crl the DER-encoded CRL
     */
    function upsertPckCrl(CA ca, bytes calldata crl) external pckCACheck(ca) returns (bytes32 attestationId) {
        attestationId = _upsertPcsCrl(ca, crl);
    }

    /**
     * Section 4.2.6 (upsertRootCACrl)
     */
    function upsertRootCACrl(bytes calldata rootcacrl) external returns (bytes32 attestationId) {
        attestationId = _upsertPcsCrl(CA.ROOT, rootcacrl);
    }

    /**
     * @notice attests collateral via the Resolver
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
        (bytes32 hash, bytes32 key, X509CRLObj memory currentCrl) = _validatePcsCrl(ca, crl);

        // attest crl timestamp
        _storePcsValidity(key, uint64(currentCrl.validityNotBefore), uint64(currentCrl.validityNotAfter));

        attestationId = _attestPcs(crl, hash, key);

        emit UpsertedPCSCollateral(ca, true);
    }

    function _validatePcsCert(CA ca, bytes calldata cert)
        private
        view
        returns (bytes32 hash, bytes32 key, X509CertObj memory currentCert)
    {
        X509Helper x509Lib = X509Helper(x509);
        currentCert = x509Lib.parseX509DER(cert);

        key = PCS_KEY(ca, false);
        hash = keccak256(currentCert.tbs);

        // Step 0: Check whether the provided certificate has been previously attested
        _checkCollateralDuplicate(key, hash);

        // Step 1: Check whether cert has expired
        bool validTimestamp =
            block.timestamp > currentCert.validityNotBefore && block.timestamp < currentCert.validityNotAfter;
        if (!validTimestamp) {
            revert Certificate_Expired(ca);
        }

        // Step 2: Rollback prevention: new certificate should not have an issued date
        // that is older than the existing certificate
        (uint64 existingCertNotValidBefore,) = _loadPcsValidity(key);
        bool outOfDate = existingCertNotValidBefore >= currentCert.validityNotBefore;
        if (outOfDate) {
            revert Certificate_Out_Of_Date();
        }

        // Step 3: Check issuer and subject common names are valid
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

        if (!LibString.eq(currentCert.issuerCommonName, ROOT_CA_COMMON_NAME)) {
            revert Invalid_Issuer_Name();
        }
        if (!LibString.eq(currentCert.subjectCommonName, expectedSubject)) {
            revert Invalid_Subject_Name();
        }

        // Step 4: Check Revocation Status
        bytes32 rootCrlKey = PCS_KEY(CA.ROOT, true);

        bytes memory rootCrlData = _fetchDataFromResolver(rootCrlKey, false);
        if (ca == CA.ROOT) {
            bytes memory pubKey = currentCert.subjectPublicKey;
            if (keccak256(pubKey) != ROOT_CA_PUBKEY_HASH) {
                revert Root_Key_Mismatch();
            }
        } else if (rootCrlData.length > 0) {
            uint256 serialNum = currentCert.serialNumber;
            bool revoked = crlLib.serialNumberIsRevoked(serialNum, rootCrlData);
            if (revoked) {
                revert Certificate_Revoked(ca, serialNum);
            }
        }

        // Step 4: Check signature
        bytes32 digest = sha256(currentCert.tbs);
        bool sigVerified;
        if (ca == CA.ROOT) {
            // the root certificate is issued by its own key
            sigVerified = verifySignature(digest, currentCert.signature, cert);
        } else {
            bytes memory rootCert = _getIssuer(CA.ROOT);
            if (rootCert.length > 0) {
                sigVerified = verifySignature(digest, currentCert.signature, rootCert);
            } else {
                // all other certificates should already have an iusuer configured
                revert Missing_Issuer();
            }
        }

        if (!sigVerified) {
            revert Invalid_Signature();
        }
    }

    function _validatePcsCrl(CA ca, bytes calldata crl)
        private
        view
        returns (bytes32 hash, bytes32 key, X509CRLObj memory currentCrl)
    {
        currentCrl = crlLib.parseCRLDER(crl);

        key = PCS_KEY(ca, true);
        hash = keccak256(currentCrl.tbs);
        _checkCollateralDuplicate(key, hash);

        // Step 1: Check whether CRL has expired
        bool validTimestamp =
            block.timestamp > currentCrl.validityNotBefore && block.timestamp < currentCrl.validityNotAfter;
        if (!validTimestamp) {
            revert Crl_Expired(ca);
        }

        // Step 2: Rollback prevention: new CRL should not have an issued date
        // that is older than the existing CRL
        (uint64 existingCrlNotValidBefore,) = _loadPcsValidity(key);
        bool outOfDate = existingCrlNotValidBefore >= currentCrl.validityNotBefore;
        if (outOfDate) {
            revert Certificate_Out_Of_Date();
        }

        // Step 3: Check CRL issuer
        string memory expectedIssuer;
        if (ca == CA.PLATFORM || ca == CA.PROCESSOR) {
            expectedIssuer = ca == CA.PLATFORM ? PCK_PLATFORM_CA_COMMON_NAME : PCK_PROCESSOR_CA_COMMON_NAME;
        } else {
            expectedIssuer = ROOT_CA_COMMON_NAME;
        }
        if (!LibString.eq(currentCrl.issuerCommonName, expectedIssuer)) {
            revert Invalid_Issuer_Name();
        }

        // Step 4: Verify signature
        bytes32 digest = sha256(currentCrl.tbs);
        bool sigVerified = verifySignature(digest, currentCrl.signature, _getIssuer(ca));
        if (!sigVerified) {
            revert Invalid_Signature();
        }
    }

    function _getIssuer(CA issuerCa) private view returns (bytes memory issuerCert) {
        bytes32 key;

        if (issuerCa == CA.PLATFORM || issuerCa == CA.PROCESSOR) {
            // this is applicable to crls only
            // since all certs in the pcsdao are issued by the root
            key = PCS_KEY(issuerCa, false);
        } else {
            key = PCS_KEY(CA.ROOT, false);
        }

        // check CA issuer expiration
        (uint64 issuerNotValidBefore, uint64 issuerNotValidAfter) = _loadPcsValidity(key);
        if (block.timestamp < issuerNotValidBefore || block.timestamp > issuerNotValidAfter) {
            // it is also possible that the issuer might be missing
            // but it requires re-upserting the issuer anyway to fix the issue
            // regardless of the error
            revert Certificate_Expired(issuerCa);
        }

        issuerCert = _fetchDataFromResolver(key, false);

        // check issuer revocation status if not root
        if (issuerCa != CA.ROOT) {
            bytes memory rootCrl = _fetchDataFromResolver(PCS_KEY(CA.ROOT, true), false);
            if (rootCrl.length > 0) {
                uint256 serialNum = X509Helper(x509).getSerialNumber(issuerCert);
                bool revoked = crlLib.serialNumberIsRevoked(serialNum, rootCrl);
                if (revoked) {
                    revert Certificate_Revoked(issuerCa, serialNum);
                }
            }
        }
    }

    function _storePcsValidity(bytes32 key, uint64 notValidBefore, uint64 notValidAfter) internal virtual;

    function _loadPcsValidity(bytes32 key)
        internal
        view
        virtual
        returns (uint64 notValidBefore, uint64 notValidAfter);
}

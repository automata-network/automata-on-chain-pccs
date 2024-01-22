// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";

/**
 * @title Intel PCS Data Access Object
 * @notice This is a core contract of our on-chain PCCS implementation as it provides methods
 * @notice to read/write essential collaterals such as the RootCA, Intermediate CAs and CRLs.
 * @notice All other DAOs are expected to configure and make external calls to this contract to fetch those collaterals.
 * @notice This contract is heavily inspired by Sections 4.2.5 and 4.2.6 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 */

abstract contract PcsDao {
    /// @notice PCS Certificates mapping
    ///
    /// @dev PCS Certificates are being submitted on-chain as is,
    /// @dev To ensure its validity, an explicit relationship attestation must be submitted
    /// @dev For example, an intermediate CA cert must linked with another attestation
    /// @dev which verifies that it is indeed signed by the legitimate Intel Root CA
    ///
    /// @dev Must ensure that the public key for the configured Intel Root CA matches with
    /// @dev the Intel source code at: https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QvE/Enclave/qve.cpp#L92-L100
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pcsCert
    mapping(CA => bytes32) public pcsCertAttestations;

    /// @notice PCS CRLs mapping
    /// @dev Verification of CRLs are conducted as part of the attestation process
    /// @dev delegated to the Entrypoint (or middleware) of the attestation protocol, such as a
    /// @dev Portal and a Module from the Verax Protocol.
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pcsCrl
    mapping(CA => bytes32) public pcsCrlAttestations;

    error Missing_Certificate(CA ca);
    error Invalid_PCK_CA(CA ca);

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
        cert = _getAttestedData(pcsCertAttestationId);

        bytes32 pcsCrlAttestationId = pcsCrlAttestations[ca];
        if (pcsCrlAttestationId != bytes32(0)) {
            crl = _getAttestedData(pcsCrlAttestationId);
        }
    }

    /**
     * Section 4.2.6 (upsertPcsCertificates)
     * @param ca replaces the "id" value with the ca_id
     * @param cert the DER-encoded certificate
     */
    function upsertPcsCertificates(CA ca, bytes calldata cert) external returns (bytes32 attestationId) {
        AttestationRequest memory req = _buildPcsAttestationRequest(false, ca, cert);
        attestationId = _attestPcs(req, ca);
        pcsCertAttestations[ca] = attestationId;
    }

    /**
     * Section 4.2.5 (upsertPckCrl)
     * @param ca either CA.PROCESSOR or CA.PLATFORM
     * @param crl the DER-encoded CRL
     */
    function upsertPckCrl(CA ca, bytes calldata crl) external pckCACheck(ca) returns (bytes32 attestationId) {
        AttestationRequest memory req = _buildPcsAttestationRequest(true, ca, crl);
        attestationId = _attestPcs(req, ca);
        pcsCrlAttestations[ca] = attestationId;
    }

    // TODO: Implement RootCRL parser. ASN.1 Structure is different from PCK CRL
    // function upsertRootCACrl(bytes calldata rootcacrl) external returns (bytes32 attestationId) {
    //     AttestationRequest memory req = _buildPcsAttestationRequest(true, CA.ROOT, rootcacrl);
    //     attestationId = _attestPcs(req, CA.ROOT);
    //     pcsCrlAttestations[CA.ROOT] = attestationId;
    // }

    function pcsCertSchemaID() public view virtual returns (bytes32 PCS_CERT_SCHEMA_ID);

    function pcsCrlSchemaID() public view virtual returns (bytes32 PCS_CRL_SCHEMA_ID);

    /**
     * @dev implement getter logic to retrieve attestation data
     * @param attestationId maps to the data
     */
    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    /**
     * @dev implement logic to validate and attest PCS Certificates or CRLs
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestPcs(AttestationRequest memory req, CA ca) internal virtual returns (bytes32 attestationId);

    /**
     * @notice builds an EAS compliant attestation request
     * @param isCrl - true only if the attested data is a CRL
     * @param blob represents the corresponding DER-encoded value, specified by isCrl and CA
     */
    function _buildPcsAttestationRequest(bool isCrl, CA ca, bytes calldata blob)
        private
        view
        returns (AttestationRequest memory req)
    {
        bytes32 predecessorAttestationId = isCrl ? pcsCrlAttestations[ca] : pcsCertAttestations[ca];
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: blob,
            value: 0
        });
        bytes32 schemaId = isCrl ? pcsCrlSchemaID() : pcsCertSchemaID();
        req = AttestationRequest({schema: schemaId, data: reqData});
    }
}

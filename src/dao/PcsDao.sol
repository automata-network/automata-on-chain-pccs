// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";

abstract contract PcsDao {
    /// @notice PCS Certificates mapping
    /// @dev A setter for this mapping must be ACCESS-CONTROLLED
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
    /// A tuple of (uint8, bytes)
    /// - uint8 ca
    /// - bytes pcsCert
    mapping(CA => bytes32) public pcsCertAttestations;

    /// @notice PCS CRLs mapping
    /// @dev Verification of CRLs are conducted as part of the attestation process
    /// @dev delegated to the Entrypoint (or middleware) of the attestation protocol, such as a
    /// @dev Portal and a Module from the Verax Protocol.
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (uint8, bytes)
    /// - uint8 ca
    /// - bytes pcsCrl
    mapping(CA => bytes32) public pcsCrlAttestations;

    // /// @notice PCS Certificate Chain mapping
    // /// key: keccak256(certAttestationId ++ issuerCertAttestationId)
    // ///
    // /// A tuple of (bytes32, string, bytes32)
    // /// bytes32 certAttestationId
    // /// string message = "is issuedBy"
    // /// bytes32 issuerCertAttestationId
    // ///
    // /// @notice On the Verax protocol, the certificate chain attestation will comform to the Relationship Schema
    // /// https://docs.ver.ax/verax-documentation/developer-guides/for-attestation-issuers/link-attestations
    // mapping(bytes32 => bytes32) public pcsCertchains;

    error Missing_Certificate(CA ca);
    error Missing_CRL(CA ca);
    error Invalid_PCK_CA(CA ca);
    error Cert_Chain_Configured();

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert Invalid_PCK_CA(ca);
        }
        _;
    }

    // function verifyCertchain(bytes32 certAttestationId, bytes32 issuerAttestationId) public view returns (bool) {
    //     return pcsCertchains[_getCertchainKey(certAttestationId, issuerAttestationId)] != bytes32(0);
    // }

    /// @dev the return value comforms with the pcs_certificates schema as defined in the Intel PCCS Design Guide
    /// @return a tuple of (cert, crl)
    function getCertificateById(CA ca) external view returns (bytes memory, bytes memory) {
        bytes32 pcsCertAttestationId = pcsCertAttestations[ca];
        if (pcsCertAttestationId == bytes32(0)) {
            revert Missing_Certificate(ca);
        }
        bytes memory cert = _getAttestedData(pcsCertAttestationId);

        bytes memory crl;
        bytes32 pcsCrlAttestationId = pcsCrlAttestations[ca];
        if (pcsCrlAttestationId != bytes32(0)) {
            crl = _getAttestedData(pcsCrlAttestationId);
        }

        return (cert, crl);
    }

    function upsertPcsCertificates(CA ca, bytes calldata cert) external {
        AttestationRequest memory req = _buildPcsAttestationRequest(false, ca, cert);
        bytes32 attestationId = _attestPcs(req);
        pcsCertAttestations[ca] = attestationId;
    }

    function upsertPckCrl(CA ca, bytes calldata crl) external pckCACheck(ca) {
        AttestationRequest memory req = _buildPcsAttestationRequest(true, ca, crl);
        bytes32 attestationId = _attestPcs(req);
        pcsCertAttestations[ca] = attestationId;
    }

    function upsertRootCACrl(bytes calldata rootcacrl) external {
        AttestationRequest memory req = _buildPcsAttestationRequest(true, CA.ROOT, rootcacrl);
        bytes32 attestationId = _attestPcs(req);
        pcsCertAttestations[CA.ROOT] = attestationId;
    }

    // function upsertPckCertificateIssuerChain(CA ca) external pckCACheck(ca) {
    //     bytes32 pckIntermediateCertAttestationId = pcsCertAttestations[ca];
    //     if (pckIntermediateCertAttestationId == bytes32(0)) {
    //         revert Missing_Certificate(ca);
    //     }
    //     bytes32 issuerCertAttestationId = pcsCertAttestations[CA.ROOT];
    //     if (issuerCertAttestationId == bytes32(0)) {
    //         revert Missing_Certificate(CA.ROOT);
    //     }
    //     _upsertCertChain(pckIntermediateCertAttestationId, issuerCertAttestationId);
    // }

    // function upsertPckCrlCertchain(CA ca) external pckCACheck(ca) {
    //     bytes32 pckCrlAttestationId = pcsCrlAttestations[ca];
    //     if (pckCrlAttestationId == bytes32(0)) {
    //         revert Missing_CRL(ca);
    //     }
    //     bytes32 issuerCertAttestationId = pcsCertAttestations[ca];
    //     if (issuerCertAttestationId == bytes32(0)) {
    //         revert Missing_Certificate(ca);
    //     }
    //     _upsertCertChain(pckCrlAttestationId, issuerCertAttestationId);
    // }

    // /// @dev Both TCBInfo and Enclave Identity are signed by the Intel Signing CA
    // function upsertSignerChain() external {
    //     bytes32 signingCertAttestationId = pcsCrlAttestations[CA.SIGNING];
    //     if (signingCertAttestationId == bytes32(0)) {
    //         revert Missing_Certificate(CA.SIGNING);
    //     }
    //     bytes32 issuerCertAttestationId = pcsCertAttestations[CA.ROOT];
    //     if (issuerCertAttestationId == bytes32(0)) {
    //         revert Missing_Certificate(CA.ROOT);
    //     }
    //     _upsertCertChain(signingCertAttestationId, issuerCertAttestationId);
    // }

    function pcsCertSchemaID() public view virtual returns (bytes32 PCS_CERT_SCHEMA_ID);

    function pcsCrlSchemaID() public view virtual returns (bytes32 PCS_CRL_SCHEMA_ID);

    // function certificateChainSchemaID() public view virtual returns (bytes32 CERTIFICATE_CHAIN_SCHEMA_ID);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _attestPcs(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    // function _attestCertChain(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

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
            data: abi.encode(ca, blob),
            value: 0
        });
        bytes32 schemaId = isCrl ? pcsCrlSchemaID() : pcsCertSchemaID();
        req = AttestationRequest({schema: schemaId, data: reqData});
    }

    // function _getCertchainKey(bytes32 certAttestationId, bytes32 issuerAttestationId)
    //     private
    //     pure
    //     returns (bytes32 key)
    // {
    //     key = keccak256(abi.encodePacked(certAttestationId, issuerAttestationId));
    // }

    // function _upsertCertChain(bytes32 certAttestationId, bytes32 issuerAttestationId) private {
    //     bytes32 key = _getCertchainKey(certAttestationId, issuerAttestationId);
    //     if (pcsCertchains[key] != bytes32(0)) {
    //         revert Cert_Chain_Configured();
    //     }
    //     bytes memory attestationData = abi.encode(certAttestationId, "is issued by", issuerAttestationId);
    //     AttestationRequestData memory reqData = AttestationRequestData({
    //         recipient: msg.sender,
    //         expirationTime: 0,
    //         revocable: false,
    //         refUID: bytes32(0),
    //         data: attestationData,
    //         value: 0
    //     });
    //     AttestationRequest memory req = AttestationRequest({schema: certificateChainSchemaID(), data: reqData});
    //     bytes32 attestationId = _attestCertChain(req);
    //     pcsCertchains[key] = attestationId;
    // }
}

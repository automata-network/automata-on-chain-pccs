// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AbstractPortal} from "@consensys/linea-attestation-registry-contracts/abstracts/AbstractPortal.sol";
import {AttestationPayload, Attestation} from "@consensys/linea-attestation-registry-contracts/types/Structs.sol";
import {PcsDao, AttestationRequest, CA} from "../../dao/PcsDao.sol";

contract PcsDaoPortal is PcsDao, AbstractPortal {
    /// @notice Error thrown when trying to revoke an attestation
    error No_Revocation();
    /// @notice Error thrown when trying to bulk revoke attestations
    error No_BulkRevocation();
    /// @notice Error thrown when trying to improperly make attestations
    error No_External_Attestation();
    /// @notice Error thrown when trying to retrieve an attestation that has been revoked/replaced
    error Attestation_Revoked(bytes32 predecessor, bytes32 successor);

    bool private _unlock;

    constructor(address[] memory modules, address router) AbstractPortal(modules, router) {}

    modifier locked() {
        if (!_unlock) {
            revert No_External_Attestation();
        }
        _;
    }

    /// @inheritdoc AbstractPortal
    function withdraw(address payable to, uint256 amount) external override {}

    function pcsCertSchemaID() public pure override returns (bytes32 PCS_CERT_SCHEMA_ID) {
        // keccak256(bytes("uint8 ca, bytes pcsCert"))
        PCS_CERT_SCHEMA_ID = 0xa5dd9ea626846139a00bf8107f573859ba67f5e9a1afd49ed46b68f653276a40;
    }

    function pcsCrlSchemaID() public pure override returns (bytes32 PCS_CRL_SCHEMA_ID) {
        // keccak256(bytes("uint8 ca, bytes pcsCrl"))
        PCS_CRL_SCHEMA_ID = 0x934a822069030e1200f83fcb82353abee65dde383eab58d55f6833bb084aca78;
    }

    // function certificateChainSchemaID() public pure override returns (bytes32 CERTIFICATE_CHAIN_SCHEMA_ID) {
    //     // https://docs.ver.ax/verax-documentation/developer-guides/for-attestation-issuers/link-attestations
    //     CERTIFICATE_CHAIN_SCHEMA_ID = 0x89bd76e17fd84df8e1e448fa1b46dd8d97f7e8e806552b003f8386a5aebcb9f0;
    // }

    function _attestPcs(AttestationRequest memory req, CA ca, bool isCrl)
        internal
        override
        returns (bytes32 attestationId)
    {
        _unlock = true;

        bytes[] memory validationPayload = new bytes[](1);

        if (isCrl) {
            validationPayload[0] = _getIssuer(ca);
        } else {
            validationPayload[0] = _getIssuer(CA.ROOT);
        }

        AttestationPayload memory attestationPayload =
            AttestationPayload(req.schema, req.data.expirationTime, abi.encodePacked(req.data.recipient), req.data.data);

        uint32 attestationIdCounter = attestationRegistry.getAttestationIdCounter();
        attestationId = bytes32(abi.encode(attestationIdCounter));

        bytes32 predecessor = req.data.refUID;
        if (predecessor == bytes32(0)) {
            super.attest(attestationPayload, validationPayload);
        } else {
            super.replace(predecessor, attestationPayload, validationPayload);
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

    function _onAttest(AttestationPayload memory, /*attestationPayload*/ address, /*attester*/ uint256 /*value*/ )
        internal
        override
        locked
    {}

    function _onBulkAttest(
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {}

    function _onReplace(
        bytes32, /*attestationId*/
        AttestationPayload memory, /*attestationPayload*/
        address, /*attester*/
        uint256 /*value*/
    ) internal override locked {}

    function _onBulkReplace(
        bytes32[] memory, /*attestationIds*/
        AttestationPayload[] memory, /*attestationsPayloads*/
        bytes[][] memory /*validationPayloads*/
    ) internal override locked {}

    /**
     * @inheritdoc AbstractPortal
     * @notice This portal doesn't allow for an attestation to be revoked
     */
    function _onRevoke(bytes32 /*attestationId*/ ) internal pure override {
        revert No_Revocation();
    }

    /**
     * @inheritdoc AbstractPortal
     * @notice This portal doesn't allow for attestations to be revoked
     */
    function _onBulkRevoke(bytes32[] memory /*attestationIds*/ ) internal pure override {
        revert No_BulkRevocation();
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
}

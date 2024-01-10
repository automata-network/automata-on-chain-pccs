// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";

abstract contract PckDao {
    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ cpuSvn ++ pceSvn)
    mapping(bytes32 => bytes32) pckCertAttestations;

    event PCKMissing(string qeid, string pceid, string cpusvn, string pcesvn);

    function getCert(string calldata qeid, string calldata pceid, string calldata cpusvn, string calldata pcesvn)
        external
        returns (bytes memory pckCert)
    {
        bytes32 attestationId = _getPckAttestationId(qeid, pceid, cpusvn, pcesvn);
        if (attestationId == bytes32(0)) {
            emit PCKMissing(qeid, pceid, cpusvn, pcesvn);
        } else {
            bytes memory attestedPckData = _getAttestedData(attestationId);
            (pckCert,,) = abi.decode(attestedPckData, (bytes, uint64, uint64));
        }
    }

    /// @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
    /// @dev for performing ECDSA verification on the provided PCK Certs prior to attestations
    function upsertPckCert(
        CA ca,
        string calldata qeid,
        string calldata pceid,
        string calldata cpusvn,
        string calldata pcesvn,
        bytes calldata cert
    ) external {
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeid, pceid, cpusvn, pcesvn, cert);
        bytes32 attestationId = _attestPck(req, ca);
        pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, cpusvn, pcesvn))] = attestationId;
    }

    function getPckCertChain(CA ca)
        external
        view
        returns (bytes memory intermediateCert, bytes memory rootCert)
    {
        // TODO
    }

    function pckSchemaID() public view virtual returns (bytes32 PCK_SCHEMA_ID);

    function _attestPck(AttestationRequest memory req, CA ca) internal virtual returns (bytes32 attestationId);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _getPckAttestationId(
        string calldata qeid,
        string calldata pceid,
        string calldata cpusvn,
        string calldata pcesvn
    ) private view returns (bytes32 attestationId) {
        attestationId = pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, cpusvn, pcesvn))];
    }

    function _buildPckCertAttestationRequest(
        string calldata qeid,
        string calldata pceid,
        string calldata cpusvn,
        string calldata pcesvn,
        bytes calldata cert
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getPckAttestationId(qeid, pceid, cpusvn, pcesvn);
        uint256 createdAt;
        if (predecessorAttestationId != bytes32(0)) {
            (, createdAt,) = abi.decode(_getAttestedData(predecessorAttestationId), (bytes, uint256, uint256));
        }
        uint256 updatedAt = block.timestamp;
        bytes memory attestationData = abi.encode(cert, createdAt, updatedAt);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: attestationData,
            value: 0
        });
        req = AttestationRequest({schema: pckSchemaID(), data: reqData});
    }
}

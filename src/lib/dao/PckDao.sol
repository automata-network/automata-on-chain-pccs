// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../../Common.sol";
import {PcsDao} from "./PcsDao.sol";

abstract contract PckDao {
    PcsDao Pcs;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ cpuSvn ++ pceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (bytes, uint256, uint256)
    /// - bytes pckCert
    /// - uint256 createdAt timestamp
    /// - uint256 updatedAt timestamp
    mapping(bytes32 => bytes32) public pckCertAttestations;

    event PCKMissing(string qeid, string pceid, string cpusvn, string pcesvn);

    error Cert_Chain_Not_Verified();

    constructor(address _pcs) {
        Pcs = PcsDao(_pcs);
    }

    function getCert(string calldata qeid, string calldata pceid, string calldata cpusvn, string calldata pcesvn)
        external
        returns (bytes memory pckCert)
    {
        bytes32 attestationId = _getAttestationId(qeid, pceid, cpusvn, pcesvn);
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

    function getPckCertChain(CA ca) external view returns (bytes memory intermediateCert, bytes memory rootCert) {
        bytes32 intermediateCertAttestationId = Pcs.pcsCertAttestations(ca);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        if (!Pcs.verifyCertchain(intermediateCertAttestationId, rootCertAttestationId)) {
            revert Cert_Chain_Not_Verified();
        }
        (intermediateCert,,) = abi.decode(_getAttestedData(intermediateCertAttestationId), (bytes, uint256, uint256));
        (rootCert,,) = abi.decode(_getAttestedData(rootCertAttestationId), (bytes, uint256, uint256));
    }

    function pckSchemaID() public view virtual returns (bytes32 PCK_SCHEMA_ID);

    function _attestPck(AttestationRequest memory req, CA ca) internal virtual returns (bytes32 attestationId);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _getAttestationId(
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
        bytes32 predecessorAttestationId = _getAttestationId(qeid, pceid, cpusvn, pcesvn);
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

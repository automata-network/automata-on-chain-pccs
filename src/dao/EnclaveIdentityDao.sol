// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

abstract contract EnclaveIdentityDao {

    PcsDao Pcs;

    /// @notice retrieves the attested EnclaveIdentity from the registry
    /// key: keccak256(id ++ version)
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (bytes, uint256, uint256)
    /// - bytes identity json blob
    /// - uint256 createdAt
    /// - uint256 updatedAt
    mapping(bytes32 => bytes32) public enclaveIdentityAttestations;

    event EnclaveIdentityMissing(string id, uint256 version);

    error Cert_Chain_Not_Verified();

    constructor(address _pcs) {
        Pcs = PcsDao(_pcs);
    }

    function getEnclaveIdentity(string calldata id, uint256 version) external returns (bytes memory enclaveIdentity) {
        bytes32 attestationId = _getAttestationId(id, version);
        if (attestationId == bytes32(0)) {
            emit EnclaveIdentityMissing(id, version);
        } else {
            bytes memory attestedPckData = _getAttestedData(attestationId);
            (enclaveIdentity,,) = abi.decode(attestedPckData, (bytes, uint256, uint256));
        }
    }

    /// @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
    /// @dev for performing ECDSA verification on the provided Enclave Identity
    /// against the Signing CA key prior to attestations
    function upsertEnclaveIdentity(bytes calldata identityBlob) external {
        (AttestationRequest memory req, string memory id, uint256 version) =
            _buildEnclaveIdentityAttestationRequest(identityBlob);
        bytes32 attestationId = _attestEnclaveIdentity(req);
        enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))] = attestationId;
    }

    function getEnclaveIdentityIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        if (!Pcs.verifyCertchain(signingCertAttestationId, rootCertAttestationId)) {
            revert Cert_Chain_Not_Verified();
        }
        (signingCert,,) = abi.decode(_getAttestedData(signingCertAttestationId), (bytes, uint256, uint256));
        (rootCert,,) = abi.decode(_getAttestedData(rootCertAttestationId), (bytes, uint256, uint256));
    }

    function enclaveIdentitySchemaID() public view virtual returns (bytes32 FMSPC_TCB_SCHEMA_ID);

    function _attestEnclaveIdentity(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _getAttestationId(string memory id, uint256 version) private view returns (bytes32 attestationId) {
        attestationId = enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))];
    }

    function _buildEnclaveIdentityAttestationRequest(bytes calldata identityBlob)
        private
        view
        returns (AttestationRequest memory req, string memory id, uint256 version)
    {
        (id, version) = _parseBlobAndGetKey(identityBlob);
        bytes32 predecessorAttestationId = _getAttestationId(id, version);
        uint256 createdAt;
        if (predecessorAttestationId != bytes32(0)) {
            (, createdAt,) = abi.decode(_getAttestedData(predecessorAttestationId), (bytes, uint256, uint256));
        }
        uint256 updatedAt = block.timestamp;
        bytes memory attestationData = abi.encode(identityBlob, createdAt, updatedAt);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: attestationData,
            value: 0
        });
        req = AttestationRequest({schema: enclaveIdentitySchemaID(), data: reqData});
    }

    function _parseBlobAndGetKey(bytes calldata identityBlob)
        private
        pure
        returns (string memory id, uint256 version)
    {
        // TODO
    }
}

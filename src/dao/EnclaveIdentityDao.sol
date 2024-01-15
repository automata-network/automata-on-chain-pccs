// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

import {EnclaveIdentityHelper, EnclaveIdentityJsonObj} from "../helper/EnclaveIdentityHelper.sol";

abstract contract EnclaveIdentityDao {
    PcsDao public Pcs;
    EnclaveIdentityHelper public EnclaveIdentityLib;

    /// @notice retrieves the attested EnclaveIdentity from the registry
    /// key: keccak256(id ++ version)
    /// NOTE: the "version" indicated here is taken from the input parameter (e.g. v3 vs v4);
    /// NOT the "version" value found in the Enclave Identity JSON
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (string, bytes, uint256, uint256)
    /// - string identity json blob
    /// - bytes signature
    /// - uint256 createdAt
    /// - uint256 updatedAt
    mapping(bytes32 => bytes32) public enclaveIdentityAttestations;

    event EnclaveIdentityMissing(uint256 id, uint256 version);

    error Cert_Chain_Not_Verified();

    constructor(address _pcs, address _enclaveIdentityHelper) {
        Pcs = PcsDao(_pcs);
        EnclaveIdentityLib = EnclaveIdentityHelper(_enclaveIdentityHelper);
    }

    function getEnclaveIdentity(uint256 id, uint256 version)
        external
        returns (string memory enclaveIdentity, bytes memory signature)
    {
        bytes32 attestationId = _getAttestationId(id, version);
        if (attestationId == bytes32(0)) {
            emit EnclaveIdentityMissing(id, version);
        } else {
            bytes memory attestedIdentityData = _getAttestedData(attestationId);
            (enclaveIdentity, signature,,) = abi.decode(attestedIdentityData, (string, bytes, uint256, uint256));
        }
    }

    /// @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
    /// @dev for performing ECDSA verification on the provided Enclave Identity
    /// against the Signing CA key prior to attestations
    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
    {
        AttestationRequest memory req = _buildEnclaveIdentityAttestationRequest(id, version, enclaveIdentityObj);
        bytes32 attestationId = _attestEnclaveIdentity(req);
        enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))] = attestationId;
    }

    function getEnclaveIdentityIssuerChain() public view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        if (!Pcs.verifyCertchain(signingCertAttestationId, rootCertAttestationId)) {
            revert Cert_Chain_Not_Verified();
        }
        (signingCert,,) = abi.decode(_getAttestedData(signingCertAttestationId), (bytes, uint256, uint256));
        (rootCert,,) = abi.decode(_getAttestedData(rootCertAttestationId), (bytes, uint256, uint256));
    }

    function enclaveIdentitySchemaID() public view virtual returns (bytes32 ENCLAVE_IDENTITY_SCHEMA_ID);

    function _attestEnclaveIdentity(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _getAttestationId(uint256 id, uint256 version) private view returns (bytes32 attestationId) {
        attestationId = enclaveIdentityAttestations[keccak256(abi.encodePacked(id, version))];
    }

    function _buildEnclaveIdentityAttestationRequest(
        uint256 id,
        uint256 version,
        EnclaveIdentityJsonObj calldata enclaveIdentityObj
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getAttestationId(id, version);
        uint256 createdAt;
        if (predecessorAttestationId != bytes32(0)) {
            (,, createdAt,) = abi.decode(_getAttestedData(predecessorAttestationId), (string, bytes, uint256, uint256));
        }
        uint256 updatedAt = block.timestamp;
        bytes memory attestationData =
            abi.encode(enclaveIdentityObj.identityStr, enclaveIdentityObj.signature, createdAt, updatedAt);
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
}

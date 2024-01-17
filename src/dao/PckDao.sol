// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

abstract contract PckDao {
    PcsDao public Pcs;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ cpuSvn ++ pceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pckCert
    mapping(bytes32 => bytes32) public pckCertAttestations;

    event PCKMissing(string qeid, string pceid, string cpusvn, string pcesvn);

    error Invalid_PCK_CA(CA ca);
    // error Cert_Chain_Not_Verified();

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert Invalid_PCK_CA(ca);
        }
        _;
    }

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
            pckCert = _getAttestedData(attestationId);
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
    ) external pckCACheck(ca) {
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeid, pceid, cpusvn, pcesvn, cert);
        bytes32 attestationId = _attestPck(req, ca);
        pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, cpusvn, pcesvn))] = attestationId;
    }

    function getPckCertChain(CA ca)
        public
        view
        pckCACheck(ca)
        returns (bytes memory intermediateCert, bytes memory rootCert)
    {
        bytes32 intermediateCertAttestationId = Pcs.pcsCertAttestations(ca);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        // if (!Pcs.verifyCertchain(intermediateCertAttestationId, rootCertAttestationId)) {
        //     revert Cert_Chain_Not_Verified();
        // }
        intermediateCert = _getAttestedData(intermediateCertAttestationId);
        rootCert = _getAttestedData(rootCertAttestationId);
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
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: cert,
            value: 0
        });
        req = AttestationRequest({schema: pckSchemaID(), data: reqData});
    }
}

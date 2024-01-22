// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

/**
 * @title Intel PCK Certificate Data Access Object
 * @notice This contract is heavily inspired by Sections 4.2.2 and 4.2.4 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 */

abstract contract PckDao {
    PcsDao public Pcs;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ cpuSvn ++ pceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pckCert
    mapping(bytes32 => bytes32) public pckCertAttestations;

    event PCKMissing(string qeid, string pceid, string cpusvn, string pcesvn);

    /// @notice the input CA parameter can only be either PROCESSOR or PLATFORM
    error Invalid_PCK_CA(CA ca);

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert Invalid_PCK_CA(ca);
        }
        _;
    }

    constructor(address _pcs) {
        Pcs = PcsDao(_pcs);
    }

    /**
     * @notice Section 4.2.2 (getCert(qe_id, cpu_svn, pce_svn, pce_id))
     * @notice The ordering of arguments is slightly different from the interface specified in the design guideline
     */
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

    /**
     * @notice Modified from Section 4.2.2 (upsertPckCert)
     * @notice This method requires an additional CA parameter, because the on-chain PCCS does not
     * store any data that is contained in the PLATFORMS table.
     * @notice Therefore, there is no way to form a mapping between (qeid, pceid) to its corresponding CA.
     * @notice Hence, it is explicitly required to be stated here.
     * @param cert DER-encoded PCK Leaf Certificate
     * @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
     * @dev for performing ECDSA verification on the provided PCK Certs prior to attestations
     */
    function upsertPckCert(
        CA ca,
        string calldata qeid,
        string calldata pceid,
        string calldata cpusvn,
        string calldata pcesvn,
        bytes calldata cert
    ) external pckCACheck(ca) returns (bytes32 attestationId) {
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeid, pceid, cpusvn, pcesvn, cert);
        attestationId = _attestPck(req, ca);
        pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, cpusvn, pcesvn))] = attestationId;
    }

    /**
     * Queries PCK Certificate issuer chain for the input ca.
     * @param ca is either CA.PROCESSOR (uint8(1)) or CA.PLATFORM ((uint8(2)))
     * @return intermediateCert - the corresponding intermediate PCK CA (DER-encoded)
     * @return rootCert - Intel SGX Root CA (DER-encoded)
     */
    function getPckCertChain(CA ca)
        public
        view
        pckCACheck(ca)
        returns (bytes memory intermediateCert, bytes memory rootCert)
    {
        bytes32 intermediateCertAttestationId = Pcs.pcsCertAttestations(ca);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        intermediateCert = _getAttestedData(intermediateCertAttestationId);
        rootCert = _getAttestedData(rootCertAttestationId);
    }

    /**
     * @dev overwrite this method to define the schemaID for the attestation of PCK Certificates
     */
    function pckSchemaID() public view virtual returns (bytes32 PCK_SCHEMA_ID);

     /**
     * @dev implement logic to validate and attest PCK Certificates
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestPck(AttestationRequest memory req, CA ca) internal virtual returns (bytes32 attestationId);

    /**
     * @dev implement getter logic to retrieve attestation data
     * @param attestationId maps to the data
     */
    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getAttestationId(
        string calldata qeid,
        string calldata pceid,
        string calldata cpusvn,
        string calldata pcesvn
    ) private view returns (bytes32 attestationId) {
        attestationId = pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, cpusvn, pcesvn))];
    }

    /**
     * @notice builds an EAS compliant attestation request
     */
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

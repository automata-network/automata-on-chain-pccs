// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PckDao} from "./PckDao.sol";

/**
 * @title Intel PCS Platform TCBs Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.8 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 */

abstract contract PlatformTcbsDao {
    PckDao public Pck;

    /// @notice retrieves the attested TCBm from the registry
    /// key: keccak256(qeid ++ pceid ++ platformCpuSvn ++ platformPceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// - string tcbm
    mapping(bytes32 => bytes32) public tcbmAttestations;

    event TCBmMissing(string qeid, string pceid, string platformCpuSvn, string platformPceSvn);

    error PckMissing();

    constructor(address _pck) {
        Pck = PckDao(_pck);
    }

    /**
     * @notice Modified from Section 4.2.8 (getPlatformTcbsById)
     * @dev For simplicity's sake, the contract currently requires all the necessary parameters
     * to return a single tcbm.
     * @dev the contract requires additional storage for
     * @dev an enumerable mapping for (qeid, pceid) keys to multiple TCBms.
     */
    function getPlatformTcbByIdAndSvns(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn
    ) external returns (string memory tcbm) {
        bytes32 attestationId = _getAttestationId(qeid, pceid, platformCpuSvn, platformPceSvn);
        if (attestationId == bytes32(0)) {
            emit TCBmMissing(qeid, pceid, platformCpuSvn, platformPceSvn);
        } else {
            tcbm = string(_getAttestedData(attestationId));
        }
    }

    function upsertPlatformTcbs(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata tcbm
    ) external returns (bytes32 attestationId) {
        bytes32 pckKey = keccak256(abi.encodePacked(qeid, pceid, tcbm));
        bytes32 pckAttestationId = Pck.pckCertAttestations(pckKey);
        if (pckAttestationId == bytes32(0)) {
            revert PckMissing();
        }
        AttestationRequest memory req = _buildTcbmAttestationRequest(qeid, pceid, platformCpuSvn, platformPceSvn, tcbm);
        attestationId = _attestTcbm(req);
        tcbmAttestations[_getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn)] = attestationId;
    }

    function tcbmSchemaId() public view virtual returns (bytes32 TCBM_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest TCBm
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestTcbm(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

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
        string calldata platformCpuSvn,
        string calldata platformPceSvn
    ) private view returns (bytes32 attestationId) {
        attestationId = tcbmAttestations[_getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn)];
    }

    function _buildTcbmAttestationRequest(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata tcbm
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getAttestationId(qeid, pceid, platformCpuSvn, platformPceSvn);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: bytes(tcbm),
            value: 0
        });
        req = AttestationRequest({schema: tcbmSchemaId(), data: reqData});
    }

    function _getTcbmKey(string calldata qeid, string calldata pceid, string calldata platformCpuSvn, string calldata platformPceSvn)
        private
        pure
        returns (bytes32 key)
    {
        key = keccak256(abi.encodePacked(qeid, pceid, platformCpuSvn, platformPceSvn));
    }
}

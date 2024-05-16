// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Intel PCK Certificate Data Access Object
 * @notice This contract is heavily inspired by Sections 4.2.2, 4.2.4 and 4.2.8 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @notice This contract is the combination of both PckDao and PlatformTcbsDao as described in section 4.2
 */
abstract contract PckDao {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    PcsDao public Pcs;

    /// K = keccak256(qeid ++ pceid)
    /// H = keccak256(qeid ++ pceid ++ tcbm)
    /// K => Enumerable H Set
    mapping(bytes32 => EnumerableSet.Bytes32Set) private _tcbmHSets;
    /// H => tcbm
    mapping(bytes32 => string) private _tcbmStrMap;

    /// @notice retrieves the attested TCBm from the registry
    /// key: keccak256(qeid ++ pceid ++ platformCpuSvn ++ platformPceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// - string tcbm
    mapping(bytes32 => bytes32) public tcbmAttestations;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ tcbm)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pckCert
    mapping(bytes32 => bytes32) public pckCertAttestations;

    event TCBmMissing(string qeid, string pceid, string platformCpuSvn, string platformPceSvn);
    event PCKMissing(string qeid, string pceid, string platformCpuSvn, string platformPceSvn);
    event PCKsMissing(string qeid, string pceid); // no single certs can be found by the given (qeid, pceid) pair

    /// @notice the input CA parameter can only be either PROCESSOR or PLATFORM
    error Invalid_PCK_CA(CA ca);
    /// @notice The corresponding PCK Certificate cannot be found for the given platform
    error Pck_Not_Found();

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
     * @dev implement getter logic to retrieve attestation data
     * @param attestationId maps to the data
     * @param hashOnly indicate either returns the hash of the data or the full collateral and hash
     */
    function getAttestedData(bytes32 attestationId, bool hashOnly)
        public
        view
        virtual
        returns (bytes memory attestationData);

    /**
     * @notice Section 4.2.2 (getCert(qe_id, cpu_svn, pce_svn, pce_id))
     * @notice The ordering of arguments is slightly different from the interface specified in the design guideline
     */
    function getCert(
        string calldata qeid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata pceid
    ) external returns (bytes memory pckCert) {
        bytes32 tcbmAttestationId = tcbmAttestations[_getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn)];
        string memory tcbm = string(getAttestedData(tcbmAttestationId, false));
        bytes32 attestationId = _getPckAttestationId(qeid, pceid, tcbm);
        if (attestationId == bytes32(0)) {
            emit PCKMissing(qeid, pceid, platformCpuSvn, platformPceSvn);
        } else {
            pckCert = getAttestedData(attestationId, false);
        }
    }

    function getCerts(string calldata qeid, string calldata pceid)
        external
        returns (string[] memory tcbms, bytes[] memory pckCerts)
    {
        bytes32 k = keccak256(abi.encodePacked(qeid, pceid));
        uint256 n = _tcbmHSets[k].length();
        if (n == 0) {
            emit PCKsMissing(qeid, pceid);
        } else {
            tcbms = new string[](n);
            pckCerts = new bytes[](n);
            for (uint256 i = 0; i < n; i++) {
                tcbms[i] = _tcbmStrMap[_tcbmHSets[k].at(i)];
                bytes32 attestationId = _getPckAttestationId(qeid, pceid, tcbms[i]);
                pckCerts[i] = getAttestedData(attestationId, false);
            }
        }
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
        bytes32 attestationId = _getTcbmAttestationId(qeid, pceid, platformCpuSvn, platformPceSvn);
        if (attestationId == bytes32(0)) {
            emit TCBmMissing(qeid, pceid, platformCpuSvn, platformPceSvn);
        } else {
            tcbm = string(getAttestedData(attestationId, false));
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
        string calldata tcbm,
        bytes calldata cert
    ) external pckCACheck(ca) returns (bytes32 attestationId) {
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeid, pceid, tcbm, cert);
        attestationId = _attestPck(req, ca, pceid, tcbm);
        pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, tcbm))] = attestationId;
        _upsertTcbm(qeid, pceid, tcbm);
    }

    function upsertPlatformTcbs(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata tcbm
    ) external returns (bytes32 attestationId) {
        bytes32 pckKey = keccak256(abi.encodePacked(qeid, pceid, tcbm));
        bytes32 pckAttestationId = pckCertAttestations[pckKey];
        if (pckAttestationId == bytes32(0)) {
            revert Pck_Not_Found();
        }
        bytes32 tcbmKey = _getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn);
        AttestationRequest memory req = _buildTcbmAttestationRequest(qeid, pceid, platformCpuSvn, platformPceSvn, tcbm);
        attestationId = _attestTcbm(req);
        tcbmAttestations[tcbmKey] = attestationId;
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
        (, intermediateCert) = abi.decode(getAttestedData(intermediateCertAttestationId, false), (bytes32, bytes));
        (, rootCert) = abi.decode(getAttestedData(rootCertAttestationId, false), (bytes32, bytes));
    }

    /**
     * @dev overwrite this method to define the schemaID for the attestation of PCK Certificates
     */
    function pckSchemaID() public view virtual returns (bytes32 PCK_SCHEMA_ID);

    function tcbmSchemaId() public view virtual returns (bytes32 TCBM_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest PCK Certificates
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestPck(AttestationRequest memory req, CA ca, string calldata pceid, string calldata tcbm)
        internal
        virtual
        returns (bytes32 attestationId);

    /**
     * @dev implement logic to validate and attest TCBm
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestTcbm(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getPckAttestationId(string memory qeid, string memory pceid, string memory tcbm)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, tcbm))];
    }

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getTcbmAttestationId(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn
    ) private view returns (bytes32 attestationId) {
        attestationId = tcbmAttestations[_getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn)];
    }

    /**
     * @notice builds an EAS compliant attestation request
     */
    function _buildPckCertAttestationRequest(
        string calldata qeid,
        string calldata pceid,
        string calldata tcbm,
        bytes calldata cert
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getPckAttestationId(qeid, pceid, tcbm);
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

    function _buildTcbmAttestationRequest(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata tcbm
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getTcbmAttestationId(qeid, pceid, platformCpuSvn, platformPceSvn);
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

    function _getTcbmKey(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn
    ) private pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(qeid, pceid, platformCpuSvn, platformPceSvn));
    }

    function _upsertTcbm(string calldata qeid, string calldata pceid, string calldata tcbm) private {
        bytes32 k = keccak256(abi.encodePacked(qeid, pceid));
        bytes32 h = keccak256(abi.encodePacked(qeid, pceid, tcbm));
        if (!_tcbmHSets[k].contains(h)) {
            _tcbmHSets[k].add(h);
            _tcbmStrMap[h] = tcbm;
        }
    }
}

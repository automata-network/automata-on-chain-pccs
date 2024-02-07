// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";
import {PlatformTcbsDao} from "./PlatformTcbsDao.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Intel PCK Certificate Data Access Object
 * @notice This contract is heavily inspired by Sections 4.2.2 and 4.2.4 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 */

abstract contract PckDao {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    PcsDao public Pcs;
    PlatformTcbsDao public PlatformTcbs;

    /// K = keccak256(qeid ++ pceid)
    /// H = keccak256(qeid ++ pceid ++ tcbm)
    /// K => Enumerable H Set
    mapping(bytes32 => EnumerableSet.Bytes32Set) private _tcbmHSets;
    /// H => tcbm
    mapping(bytes32 => string) private _tcbmStrMap;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ tcbm)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pckCert
    mapping(bytes32 => bytes32) public pckCertAttestations;

    event PCKMissing(string qeid, string pceid, string platformCpuSvn, string platformPceSvn);
    event PCKsMissing(string qeid, string pceid); // no single certs can be found by the given (qeid, pceid) pair

    /// @notice the input CA parameter can only be either PROCESSOR or PLATFORM
    error Invalid_PCK_CA(CA ca);
    error Not_An_Admin(address caller);

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert Invalid_PCK_CA(ca);
        }
        _;
    }

    constructor(address _pcs, address _platformTcbs) {
        Pcs = PcsDao(_pcs);
        PlatformTcbs = PlatformTcbsDao(_platformTcbs);
    }

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
        string memory tcbm = _getTcbm(qeid, platformCpuSvn, platformPceSvn, pceid);
        bytes32 attestationId = _getAttestationId(qeid, pceid, tcbm);
        if (attestationId == bytes32(0)) {
            emit PCKMissing(qeid, pceid, platformCpuSvn, platformPceSvn);
        } else {
            pckCert = _getAttestedData(attestationId);
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
                bytes32 attestationId = _getAttestationId(qeid, pceid, tcbms[i]);
                pckCerts[i] = _getAttestedData(attestationId);
            }
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
        if (!_adminOnly(msg.sender)) {
            revert Not_An_Admin(msg.sender);
        }
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeid, pceid, tcbm, cert);
        attestationId = _attestPck(req, ca);
        pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, tcbm))] = attestationId;
        _upsertTcbm(qeid, pceid, tcbm);
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
     * @dev must implement their own access-control mechanism
     * @param caller address
     */
    function _adminOnly(address caller) internal view virtual returns (bool);

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getAttestationId(string memory qeid, string memory pceid, string memory tcbm)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, tcbm))];
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
        bytes32 predecessorAttestationId = _getAttestationId(qeid, pceid, tcbm);
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

    function _getTcbm(
        string calldata qeid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata pceid
    ) private returns (string memory tcbm) {
        tcbm = PlatformTcbs.getPlatformTcbByIdAndSvns(qeid, pceid, platformCpuSvn, platformPceSvn);
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

import {FmspcTcbHelper, TcbInfoJsonObj} from "../helper/FmspcTcbHelper.sol";

abstract contract FmspcTcbDao {
    PcsDao public Pcs;
    FmspcTcbHelper public FmspcTcbLib;

    /// @notice retrieves the attested FMSPC TCBInfo from the registry
    /// key: keccak256(FMSPC ++ type ++ version)
    /// @notice the schema of the attested data is the following:
    /// A tuple of (uint256, uint256, uint256, uint256, string, bytes)
    /// - uint256 tcbType
    /// - uint256 version
    /// - uint256 issueDateTimestamp
    /// - uint256 nextUpdateTimestamp
    /// - string tcbInfo
    /// - bytes signature
    mapping(bytes32 => bytes32) public fmspcTcbInfoAttestations;

    event TCBInfoMissing(uint256 tcbType, string fmspc, uint256 version);

    // error Cert_Chain_Not_Verified();

    constructor(address _pcs, address _fmspcHelper) {
        Pcs = PcsDao(_pcs);
        FmspcTcbLib = FmspcTcbHelper(_fmspcHelper);
    }

    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        returns (string memory tcbInfo, bytes memory signature)
    {
        bytes32 attestationId = _getAttestationId(tcbType, fmspc, version);
        if (attestationId == bytes32(0)) {
            emit TCBInfoMissing(tcbType, fmspc, version);
        } else {
            bytes memory attestedTcbData = _getAttestedData(attestationId);
            (,,,, tcbInfo, signature) = abi.decode(attestedTcbData, (uint256, uint256, uint256, uint256, string, bytes));
        }
    }

    /// @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
    /// @dev for performing ECDSA verification on the provided TCBInfo against the Signing CA key prior to attestations
    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external {
        (AttestationRequest memory req, uint256 tcbType, string memory fmspc, uint256 version) =
            _buildTcbAttestationRequest(tcbInfoObj);
        bytes32 attestationId = _attestTcb(req);
        fmspcTcbInfoAttestations[keccak256(abi.encodePacked(tcbType, fmspc, version))] = attestationId;
    }

    function getTcbIssuerChain() public view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        // if (!Pcs.verifyCertchain(signingCertAttestationId, rootCertAttestationId)) {
        //     revert Cert_Chain_Not_Verified();
        // }
        signingCert = _getAttestedData(signingCertAttestationId);
        rootCert = _getAttestedData(rootCertAttestationId);
    }

    function fmspcTcbSchemaID() public view virtual returns (bytes32 FMSPC_TCB_SCHEMA_ID);

    function _attestTcb(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    function _getAttestationId(uint256 tcbType, string memory fmspc, uint256 version)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = fmspcTcbInfoAttestations[keccak256(abi.encodePacked(tcbType, fmspc, version))];
    }

    function _buildTcbAttestationRequest(TcbInfoJsonObj calldata tcbInfoObj)
        private
        view
        returns (AttestationRequest memory req, uint256 tcbType, string memory fmspc, uint256 version)
    {
        uint256 issueDate;
        uint256 nextUpdate;
        (tcbType, fmspc, version, issueDate, nextUpdate) = FmspcTcbLib.parseTcbString(tcbInfoObj.tcbInfoStr);
        bytes32 predecessorAttestationId = _getAttestationId(tcbType, fmspc, version);
        bytes memory attestationData =
            abi.encode(tcbType, version, issueDate, nextUpdate, tcbInfoObj.tcbInfoStr, tcbInfoObj.signature);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0,
            revocable: true,
            refUID: predecessorAttestationId,
            data: attestationData,
            value: 0
        });
        req = AttestationRequest({schema: fmspcTcbSchemaID(), data: reqData});
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PcsDao} from "./PcsDao.sol";

import {FmspcTcbHelper, TcbInfoJsonObj} from "../helper/FmspcTcbHelper.sol";

/**
 * @title FMSPC TCB Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.3 in the Intel SGX PCCS Design Guidelines
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with TCBInfo JSON
 * data published on-chain.
 */
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

    constructor(address _pcs, address _fmspcHelper) {
        Pcs = PcsDao(_pcs);
        FmspcTcbLib = FmspcTcbHelper(_fmspcHelper);
    }

    /**
     * @notice Section 4.2.3 (getTcbInfo)
     * @notice Queries TCB Info for the given FMSPC
     * @param tcbType 0: SGX, 1: TDX
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationParsers/src/Json/TcbInfo.cpp#L46-L47
     * @param fmspc FMSPC
     * @param version v2 or v3
     * https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/39989a42bbbb0c968153a47254b6de79a27eb603/QuoteVerification/QVL/Src/AttestationParsers/include/SgxEcdsaAttestation/AttestationParsers.h#L241-L248
     * @return tcbObj See {FmspcTcbHelper.sol} to learn more about the structure definition
     */
    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        returns (TcbInfoJsonObj memory tcbObj)
    {
        bytes32 attestationId = _getAttestationId(tcbType, fmspc, version);
        if (attestationId == bytes32(0)) {
            emit TCBInfoMissing(tcbType, fmspc, version);
        } else {
            bytes memory attestedTcbData = _getAttestedData(attestationId);
            (,,,, tcbObj.tcbInfoStr, tcbObj.signature) =
                abi.decode(attestedTcbData, (uint256, uint256, uint256, uint256, string, bytes));
        }
    }

    /**
     * @notice Section 4.2.9 (upsertEnclaveIdentity)
     * @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
     * @dev for performing ECDSA verification on the provided TCBInfo
     * against the Signing CA key prior to attestations
     * @param tcbInfoObj See {FmspcTcbHelper.sol} to learn more about the structure definition
     */
    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external returns (bytes32 attestationId) {
        (AttestationRequest memory req, uint256 tcbType, string memory fmspc, uint256 version) =
            _buildTcbAttestationRequest(tcbInfoObj);
        attestationId = _attestTcb(req);
        fmspcTcbInfoAttestations[keccak256(abi.encodePacked(tcbType, fmspc, version))] = attestationId;
    }

    /**
     * @notice Fetches the TCBInfo Issuer Chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getTcbIssuerChain() public view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        signingCert = _getAttestedData(signingCertAttestationId);
        rootCert = _getAttestedData(rootCertAttestationId);
    }

    /**
     * @dev overwrite this method to define the schemaID for the attestation of TCBInfo
     */
    function fmspcTcbSchemaID() public view virtual returns (bytes32 FMSPC_TCB_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest TCBInfo
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestTcb(AttestationRequest memory req) internal virtual returns (bytes32 attestationId);

    /**
     * @dev implement getter logic to retrieve attestation data
     * @param attestationId maps to the data
     */
    function _getAttestedData(bytes32 attestationId) internal view virtual returns (bytes memory attestationData);

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getAttestationId(uint256 tcbType, string memory fmspc, uint256 version)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = fmspcTcbInfoAttestations[keccak256(abi.encodePacked(tcbType, fmspc, version))];
    }

    /**
     * @notice builds an EAS compliant attestation request
     */
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

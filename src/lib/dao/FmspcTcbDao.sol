// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../../Common.sol";
import {PcsDao} from "./PcsDao.sol";

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";

abstract contract FmspcTcbDao {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;

    PcsDao public Pcs;

    /// @notice retrieves the attested FMSPC TCBInfo from the registry
    /// key: keccak256(FMSPC ++ type ++ version)
    ///
    /// @notice the schema of the attested data is the following:
    /// A tuple of (bytes, uint256, uint256)
    /// - bytes tcbInfoJson blob
    /// - uint256 createdAt
    /// - uint256 updatedAt
    mapping(bytes32 => bytes32) public fmspcTcbInfoAttestations;

    event TCBInfoMissing(uint256 tcbType, string fmspc, uint256 version);

    error TCBInfo_Invalid();
    error Cert_Chain_Not_Verified();

    constructor(address _pcs) {
        Pcs = PcsDao(_pcs);
    }

    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        returns (bytes memory tcbInfo)
    {
        bytes32 attestationId = _getAttestationId(tcbType, fmspc, version);
        if (attestationId == bytes32(0)) {
            emit TCBInfoMissing(tcbType, fmspc, version);
        } else {
            bytes memory attestedPckData = _getAttestedData(attestationId);
            (tcbInfo,,) = abi.decode(attestedPckData, (bytes, uint256, uint256));
        }
    }

    /// @dev Attestation Registry Entrypoint Contracts, such as Portals on Verax are responsible
    /// @dev for performing ECDSA verification on the provided TCBInfo against the Signing CA key prior to attestations
    function upsertFmspcTcb(bytes calldata tcbInfoJsonBlob) external {
        (AttestationRequest memory req, uint256 tcbType, string memory fmspc, uint256 version) =
            _buildTcbAttestationRequest(tcbInfoJsonBlob);
        bytes32 attestationId = _attestTcb(req);
        fmspcTcbInfoAttestations[keccak256(abi.encodePacked(tcbType, fmspc, version))] = attestationId;
    }

    function getTcbIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        bytes32 signingCertAttestationId = Pcs.pcsCertAttestations(CA.SIGNING);
        bytes32 rootCertAttestationId = Pcs.pcsCertAttestations(CA.ROOT);
        if (!Pcs.verifyCertchain(signingCertAttestationId, rootCertAttestationId)) {
            revert Cert_Chain_Not_Verified();
        }
        (signingCert,,) = abi.decode(_getAttestedData(signingCertAttestationId), (bytes, uint256, uint256));
        (rootCert,,) = abi.decode(_getAttestedData(rootCertAttestationId), (bytes, uint256, uint256));
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

    function _buildTcbAttestationRequest(bytes calldata tcbInfoJsonBlob)
        private
        view
        returns (AttestationRequest memory req, uint256 tcbType, string memory fmspc, uint256 version)
    {
        (tcbType, fmspc, version) = _parseBlobAndGetKey(tcbInfoJsonBlob);
        bytes32 predecessorAttestationId = _getAttestationId(tcbType, fmspc, version);
        uint256 createdAt;
        if (predecessorAttestationId != bytes32(0)) {
            (, createdAt,) = abi.decode(_getAttestedData(predecessorAttestationId), (bytes, uint256, uint256));
        }
        uint256 updatedAt = block.timestamp;
        bytes memory attestationData = abi.encode(tcbInfoJsonBlob, createdAt, updatedAt);
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

    function _parseBlobAndGetKey(bytes calldata tcbInfoJsonBlob)
        private
        pure
        returns (uint256 tcbType, string memory fmspc, uint256 version)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(string(tcbInfoJsonBlob));
        JSONParserLib.Item[] memory children = root.children();
        JSONParserLib.Item[] memory tcbInfoObj;

        uint256 tcbInfoIndex;
        for (uint256 x = 0; x < root.size(); x++) {
            string memory decodedKey = JSONParserLib.decodeString(children[x].key());
            if (decodedKey.eq("tcbInfo")) {
                tcbInfoObj = children[x].children();
                tcbInfoIndex = x;
            }
        }

        if (tcbInfoObj.length == 0) {
            revert TCBInfo_Invalid();
        }

        bool tcbTypeFound;
        bool fmspcFound;
        bool versionFound;
        bool allFound;

        for (uint256 y = 0; y < children[tcbInfoIndex].size(); y++) {
            JSONParserLib.Item memory current = tcbInfoObj[y];
            string memory decodedKey = JSONParserLib.decodeString(current.key());
            if (decodedKey.eq("tcbType")) {
                tcbType = JSONParserLib.parseUint(current.value());
                tcbTypeFound = true;
            }
            if (decodedKey.eq("fmspc")) {
                fmspc = JSONParserLib.decodeString(current.value());
                fmspcFound = true;
            }
            if (decodedKey.eq("version")) {
                version = JSONParserLib.parseUint(current.value());
                versionFound = true;
            }
            allFound = (tcbTypeFound && fmspcFound && versionFound);
            if (allFound) {
                break;
            }
        }

        if (!allFound) {
            revert TCBInfo_Invalid();
        }
    }
}

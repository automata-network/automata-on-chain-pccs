// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/auth/Ownable.sol";

import "../Common.sol";
import "../helper/EnclaveIdentityHelper.sol";
import "../helper/FmspcTcbHelper.sol";
import "../helper/X509Helper.sol";
import "../helper/X509CRLHelper.sol";

contract AccessControlledPCCS is Ownable {
    enum ID {
        INVALID,
        ROOT_CA,
        ROOT_CRL,
        PROCESSOR_CA,
        PROCESSOR_PCK_CRL,
        PLATFORM_CA,
        PLATFORM_PCK_CRL,
        TCB_SIGNING,
        QE_ID_OBJ,
        FMSPC_TCB_INFO_OBJ
    }

    EnclaveIdentityHelper public enclaveIdHelper;
    FmspcTcbHelper public fmspcTcbHelper;
    X509Helper public x509Helper;
    X509CRLHelper public x509CrlHelper;

    mapping(bytes32 attId => bytes attData) _pccsData;

    constructor(address _enclaveIdHelper, address _fmspcTcbHelper, address _x509Helper, address _x509CrlHelper) {
        _initializeOwner(msg.sender);
        enclaveIdHelper = EnclaveIdentityHelper(_enclaveIdHelper);
        fmspcTcbHelper = FmspcTcbHelper(_fmspcTcbHelper);
        x509Helper = X509Helper(_x509Helper);
        x509CrlHelper = X509CRLHelper(_x509CrlHelper);
    }

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert("Invalid PCK CA");
        }
        _;
    }

    error Missing_Data(ID id);

    function enclaveIdAttestations(bytes32 key) external pure returns (bytes32 attestationId) {
        attestationId = _computeId(ID.QE_ID_OBJ, key);
    }

    function getEnclaveIdentity(uint256 id, uint256 version)
        external
        view
        returns (EnclaveIdentityJsonObj memory enclaveIdObj)
    {
        bytes32 key = keccak256(abi.encodePacked(id, version));
        bytes32 attId = _computeId(ID.QE_ID_OBJ, key);
        bytes memory attData = _pccsData[attId];
        if (attData.length == 0) {
            revert Missing_Data(ID.QE_ID_OBJ);
        }
        (,, enclaveIdObj.identityStr, enclaveIdObj.signature) =
            abi.decode(attData, (IdentityObj, bytes32, string, bytes));
    }

    function fmspcTcbInfoAttestations(bytes32 key) external pure returns (bytes32 attestationId) {
        attestationId = _computeId(ID.FMSPC_TCB_INFO_OBJ, key);
    }

    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        view
        returns (TcbInfoJsonObj memory tcbObj)
    {
        bytes32 key = keccak256(abi.encodePacked(tcbType, fmspc, version));
        bytes32 attId = _computeId(ID.FMSPC_TCB_INFO_OBJ, key);
        bytes memory attData = _pccsData[attId];
        if (attData.length == 0) {
            revert Missing_Data(ID.FMSPC_TCB_INFO_OBJ);
        }
        (,,,,,, tcbObj.tcbInfoStr, tcbObj.signature) =
            abi.decode(attData, (uint256, uint256, uint256, uint256, TCBLevelsObj[], bytes32, string, bytes));
    }

    function pcsCertAttestations(CA ca) external pure returns (bytes32 attestationId) {
        (ID certId, ) = _getCertIdsFromCommonCAs(ca);
        attestationId = _computeId(certId, hex"");
    }

    function pcsCrlAttestations(CA ca) external pure returns (bytes32 attestationId) {
        (, ID crlId) = _getCertIdsFromCommonCAs(ca);
        attestationId = _computeId(crlId, hex"");
    }

    function getCertificateById(CA ca) external view returns (bytes memory cert, bytes memory crl) {
        (ID certId, ID crlId) = _getCertIdsFromCommonCAs(ca);

        bytes32 certAttestationId = _computeId(certId, hex"");
        bytes32 crlAttestationId = _computeId(crlId, hex"");

        (, cert) = abi.decode(_pccsData[certAttestationId], (bytes32, bytes));

        if (crlAttestationId != bytes32(0)) {
            (, crl) = abi.decode(_pccsData[crlAttestationId], (bytes32, bytes));
        }
    }

    function getAttestedData(bytes32 id) external view returns (bytes memory data) {
        data = _pccsData[id];
    }

    function upsertPcsCertificates(CA ca, bytes calldata cert) external onlyOwner returns (bytes32 attestationId) {
        (ID certId,) = _getCertIdsFromCommonCAs(ca);
        (bytes memory tbs,) = x509Helper.getTbsAndSig(cert);
        attestationId = _computeId(certId, hex"");
        _pccsData[attestationId] = abi.encode(keccak256(tbs), cert);
    }

    function upsertPckCrl(CA ca, bytes calldata crl)
        external
        pckCACheck(ca)
        onlyOwner
        returns (bytes32 attestationId)
    {
        attestationId = _upsertCrl(ca, crl);
    }

    function upsertRootCACrl(bytes calldata rootcacrl) external returns (bytes32 attestationId) {
        attestationId = _upsertCrl(CA.ROOT, rootcacrl);
    }

    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external returns (bytes32 attestationId) {
        (bytes memory data, uint256 tcbType, string memory fmspc, uint256 version) =
            _buildTcbAttestationData(tcbInfoObj.tcbInfoStr, tcbInfoObj.signature);
        bytes32 key = keccak256(abi.encodePacked(tcbType, fmspc, version));
        attestationId = _computeId(ID.FMSPC_TCB_INFO_OBJ, key);
        _pccsData[attestationId] = data;
    }

    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
        returns (bytes32 attestationId)
    {
        IdentityObj memory identity = enclaveIdHelper.parseIdentityString(enclaveIdentityObj.identityStr);
        bytes32 digest = sha256(bytes(enclaveIdentityObj.identityStr));
        bytes memory data = abi.encode(identity, digest, enclaveIdentityObj.identityStr, enclaveIdentityObj.signature);
        bytes32 key = keccak256(abi.encodePacked(id, version));
        attestationId = _computeId(ID.QE_ID_OBJ, key);
        _pccsData[attestationId] = data;
    }

    function _getCertIdsFromCommonCAs(CA ca) private pure returns (ID certId, ID crlId) {
        if (ca == CA.ROOT) {
            certId = ID.ROOT_CA;
            crlId = ID.ROOT_CRL;
        } else if (ca == CA.PLATFORM) {
            certId = ID.PLATFORM_CA;
            crlId = ID.PLATFORM_PCK_CRL;
        } else if (ca == CA.PROCESSOR) {
            certId = ID.PROCESSOR_CA;
            crlId = ID.PROCESSOR_PCK_CRL;
        } else if (ca == CA.SIGNING) {
            certId = ID.TCB_SIGNING;
        }
    }

    function _upsertCrl(CA ca, bytes calldata crl) private returns (bytes32 attestationId) {
        (, ID crlId) = _getCertIdsFromCommonCAs(ca);
        (bytes memory tbs,) = x509CrlHelper.getTbsAndSig(crl);
        attestationId = _computeId(crlId, hex"");
        _pccsData[attestationId] = abi.encode(keccak256(tbs), crl);
    }

    function _buildTcbAttestationData(string memory tcbInfoStr, bytes memory signature)
        private
        view
        returns (bytes memory attestationData, uint256 tcbType, string memory fmspc, uint256 version)
    {
        (, TCBLevelsObj[] memory tcbLevels) = fmspcTcbHelper.parseTcbLevels(tcbInfoStr);
        uint256 issueDate;
        uint256 nextUpdate;
        (tcbType, fmspc, version, issueDate, nextUpdate) = fmspcTcbHelper.parseTcbString(tcbInfoStr);
        attestationData = abi.encode(
            tcbType, version, issueDate, nextUpdate, tcbLevels, sha256(bytes(tcbInfoStr)), tcbInfoStr, signature
        );
    }

    function _computeId(ID id, bytes32 key) private pure returns (bytes32 attId) {
        if (key != bytes32(0)) {
            attId = keccak256(abi.encodePacked(id, key));
        } else {
            attId = bytes32(uint256(uint8(id)));
        }
    }
}

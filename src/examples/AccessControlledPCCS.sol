// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/auth/Ownable.sol";
import "solady/utils/LibString.sol";

import "../Common.sol";
import "../helpers/EnclaveIdentityHelper.sol";
import "../helpers/FmspcTcbHelper.sol";
import "../helpers/X509Helper.sol";
import "../helpers/X509CRLHelper.sol";

/**
 * @title Access Controlled PCCS Contract Example
 * @notice This is a simplified example of a PCCS implements a union of all DAO methods,
 * that extends the Ownable library such that only a trusted set of addresses can upsert collaterals.
 */
contract AccessControlledPCCS is Ownable {
    using LibString for string;

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

    error Missing_Data(ID id);

    // === DaoBase ===

    function getAttestedData(bytes32 id, bool hashOnly) external view returns (bytes memory data) {
        if (hashOnly) {
            data = _pccsData[id];
        } else {
            bytes memory metaData = _pccsData[id];
            (bytes32 dataHash, bytes32 dataAttestationId) = abi.decode(metaData, (bytes32, bytes32));
            data = abi.encode(dataHash, _pccsData[dataAttestationId]);
        }
    }

    // === EnclaveIdDao ===

    function enclaveIdentityAttestations(bytes32 key) external view returns (bytes32 attestationId) {
        attestationId = _computeId(ID.QE_ID_OBJ, keccak256(abi.encodePacked(key)));
        uint256 len = _pccsData[attestationId].length;
        if (len == 0) {
            return bytes32(0);
        }
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
        (, enclaveIdObj.identityStr, enclaveIdObj.signature) = abi.decode(attData, (IdentityObj, string, bytes));
    }

    function upsertEnclaveIdentity(uint256 id, uint256 version, EnclaveIdentityJsonObj calldata enclaveIdentityObj)
        external
        onlyOwner
        returns (bytes32 attestationId)
    {
        IdentityObj memory identity = enclaveIdHelper.parseIdentityString(enclaveIdentityObj.identityStr);
        bytes32 digest = sha256(bytes(enclaveIdentityObj.identityStr));
        bytes memory data = abi.encode(identity, enclaveIdentityObj.identityStr, enclaveIdentityObj.signature);
        bytes32 key = keccak256(abi.encodePacked(id, version));
        attestationId = _attestCollateral(ID.QE_ID_OBJ, key, data, digest);
    }

    // === Fmspc DAO ===

    function fmspcTcbInfoAttestations(bytes32 key) external view returns (bytes32 attestationId) {
        attestationId = _computeId(ID.FMSPC_TCB_INFO_OBJ, keccak256(abi.encodePacked(key)));
        uint256 len = _pccsData[attestationId].length;
        if (len == 0) {
            return bytes32(0);
        }
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
        if (version == 2) {
            (,,,,, tcbObj.tcbInfoStr, tcbObj.signature) =
                abi.decode(attData, (uint256, uint256, uint256, uint256, TCBLevelsObj[], string, bytes));
        } else if (version == 3) {
            (,,,,,,,, tcbObj.tcbInfoStr, tcbObj.signature) = abi.decode(
                attData,
                (
                    uint256,
                    string,
                    uint256,
                    uint256,
                    uint256,
                    TCBLevelsObj[],
                    TDXModule,
                    TDXModuleIdentity[],
                    string,
                    bytes
                )
            );
        }
    }

    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external onlyOwner returns (bytes32 attestationId) {
        (bytes memory data, TcbInfoBasic memory tcbInfo) =
            _buildTcbAttestationData(tcbInfoObj.tcbInfoStr, tcbInfoObj.signature);
        bytes32 key = keccak256(abi.encodePacked(tcbInfo.id, tcbInfo.fmspc, tcbInfo.version));
        attestationId = _attestCollateral(ID.FMSPC_TCB_INFO_OBJ, key, data, sha256(bytes(tcbInfoObj.tcbInfoStr)));
    }

    function _buildTcbAttestationData(string memory tcbInfoStr, bytes memory signature)
        private
        view
        returns (bytes memory attestationData, TcbInfoBasic memory tcbInfo)
    {
        (, TCBLevelsObj[] memory tcbLevels) = fmspcTcbHelper.parseTcbLevels(tcbInfoStr);
        tcbInfo = fmspcTcbHelper.parseTcbString(tcbInfoStr);
        if (tcbInfo.version == 2) {
            attestationData = abi.encode(
                tcbInfo.tcbType,
                tcbInfo.version,
                tcbInfo.issueDate,
                tcbInfo.nextUpdate,
                tcbLevels,
                tcbInfoStr,
                signature
            );
        } else if (tcbInfo.version == 3) {
            TDXModule memory tdxModule;
            TDXModuleIdentity[] memory tdxModuleIdentities;
            if (tcbInfo.id == TcbId.TDX) {
                (tdxModule, tdxModuleIdentities) = fmspcTcbHelper.parseTcbTdxModules(tcbInfoStr);
            }
            attestationData = abi.encode(
                tcbInfo.tcbType,
                tcbInfo.id,
                tcbInfo.version,
                tcbInfo.issueDate,
                tcbInfo.nextUpdate,
                tcbLevels,
                tdxModule,
                tdxModuleIdentities,
                tcbInfoStr,
                signature
            );
        }
    }

    // === PcsDao ===

    modifier pckCACheck(CA ca) {
        if (ca == CA.ROOT || ca == CA.SIGNING) {
            revert("Invalid PCK CA");
        }
        _;
    }

    function pcsCertAttestations(CA ca) external view returns (bytes32 attestationId) {
        (ID certId,) = _getCertIdsFromCommonCAs(ca);
        attestationId = _computeId(certId, keccak256(abi.encodePacked(bytes32(0))));
        uint256 len = _pccsData[attestationId].length;
        if (len == 0) {
            return bytes32(0);
        }
    }

    function pcsCrlAttestations(CA ca) external view returns (bytes32 attestationId) {
        (, ID crlId) = _getCertIdsFromCommonCAs(ca);
        attestationId = _computeId(crlId, keccak256(abi.encodePacked(bytes32(0))));
        uint256 len = _pccsData[attestationId].length;
        if (len == 0) {
            return bytes32(0);
        }
    }

    function getCertificateById(CA ca) external view returns (bytes memory cert, bytes memory crl) {
        (ID certId, ID crlId) = _getCertIdsFromCommonCAs(ca);

        bytes32 certAttestationId = _computeId(certId, hex"");
        bytes32 crlAttestationId = _computeId(crlId, hex"");

        bytes memory certData = _pccsData[certAttestationId];
        if (certData.length == 0) {
            revert Missing_Data(certId);
        }

        cert = certData;

        bytes memory crlData = _pccsData[crlAttestationId];
        if (crlData.length > 0) {
            crl = crlData;
        }
    }

    function upsertPcsCertificates(CA ca, bytes calldata cert) external onlyOwner returns (bytes32 attestationId) {
        (ID certId,) = _getCertIdsFromCommonCAs(ca);
        (bytes memory tbs,) = x509Helper.getTbsAndSig(cert);
        attestationId = _attestCollateral(certId, bytes32(0), cert, keccak256(tbs));
    }

    function upsertPckCrl(CA ca, bytes calldata crl)
        external
        pckCACheck(ca)
        onlyOwner
        returns (bytes32 attestationId)
    {
        attestationId = _upsertCrl(ca, crl);
    }

    function upsertRootCACrl(bytes calldata rootcacrl) external onlyOwner returns (bytes32 attestationId) {
        attestationId = _upsertCrl(CA.ROOT, rootcacrl);
    }

    /// === Helper Functions ===

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
        attestationId = _attestCollateral(crlId, bytes32(0), crl, keccak256(tbs));
    }

    function _attestCollateral(ID id, bytes32 key, bytes memory data, bytes32 dataHash)
        private
        returns (bytes32 metaAttestationId)
    {
        bytes32 dataAttestationId = _computeId(id, key);
        metaAttestationId = _computeId(id, keccak256(abi.encodePacked(key)));
        _pccsData[dataAttestationId] = data;
        _pccsData[metaAttestationId] = abi.encode(dataHash, dataAttestationId);
    }

    function _computeId(ID id, bytes32 key) private pure returns (bytes32 attId) {
        if (key != bytes32(0)) {
            attId = keccak256(abi.encodePacked(id, key));
        } else {
            attId = bytes32(uint256(uint8(id)));
        }
    }
}

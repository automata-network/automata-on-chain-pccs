// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao} from "./PcsDao.sol";
import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

import {CA} from "../Common.sol";
import {
    FmspcTcbHelper,
    TcbInfoJsonObj,
    TcbId,
    TcbInfoBasic,
    TCBLevelsObj,
    TDXModule,
    TDXModuleIdentity
} from "../helpers/FmspcTcbHelper.sol";

/// @notice the on-chain schema of the attested data is dependent on the version of TCBInfo:
/// @notice For TCBInfoV2, it consists of the ABI-encoded tuple of:
/// @notice (TcbInfoBasic, TCBLevelsObj[], string tcbInfo, bytes signature)
/// @notice For TCBInfoV3, it consists of the abi-encoded tuple of:
/// @notice (TcbInfoBasic, TDXModule, TDXModuleIdentity[], TCBLevelsObj, string tcbInfo, bytes signature)
/// @notice See {{ FmspcTcbHelper.sol }} to learn more about FMSPC TCB related struct definitions.

/**
 * @title FMSPC TCB Data Access Object
 * @notice This contract is heavily inspired by Section 4.2.3 in the Intel SGX PCCS Design Guidelines
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @dev should extends this contract and use the provided read/write methods to interact with TCBInfo JSON
 * data published on-chain.
 */
abstract contract FmspcTcbDao is DaoBase, SigVerifyBase {
    PcsDao public Pcs;
    FmspcTcbHelper public FmspcTcbLib;

    // first 4 bytes of FMSPC_TCB_MAGIC
    bytes4 constant FMSPC_TCB_MAGIC = 0xbb69b29c;

    // 8de7233f
    error Invalid_TCB_Cert_Signature();
    // bae57649
    error TCB_Expired();

    constructor(address _resolver, address _p256, address _pcs, address _fmspcHelper, address _x509Helper)
        SigVerifyBase(_p256, _x509Helper)
        DaoBase(_resolver)
    {
        Pcs = PcsDao(_pcs);
        FmspcTcbLib = FmspcTcbHelper(_fmspcHelper);
    }

    /**
     * @notice computes the key that is mapped to the collateral attestation ID
     * @return key = keccak256(type ++ FMSPC ++ version)
     */
    function FMSPC_TCB_KEY(uint8 tcbType, bytes6 fmspc, uint32 version) public pure returns (bytes32 key) {
        key = keccak256(abi.encodePacked(FMSPC_TCB_MAGIC, tcbType, fmspc, version));
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
        view
        returns (TcbInfoJsonObj memory tcbObj)
    {
        bytes6 fmspcBytes = bytes6(uint48(_parseUintFromHex(fmspc)));
        bytes memory attestedTcbData =
            _onFetchDataFromResolver(FMSPC_TCB_KEY(uint8(tcbType), fmspcBytes, uint32(version)), false);
        if (version < 3) {
            (,, tcbObj.tcbInfoStr, tcbObj.signature) =
                abi.decode(attestedTcbData, (TcbInfoBasic, TCBLevelsObj[], string, bytes));
        } else {
            (,,,, tcbObj.tcbInfoStr, tcbObj.signature) = abi.decode(
                attestedTcbData, (TcbInfoBasic, TDXModule, TDXModuleIdentity[], TCBLevelsObj[], string, bytes)
            );
        }
    }

    /**
     * @notice Section 4.2.9 (upsertEnclaveIdentity)
     * @param tcbInfoObj See {FmspcTcbHelper.sol} to learn more about the structure definition
     */
    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external returns (bytes32 attestationId) {
        _validateTcbInfo(tcbInfoObj);
        (bytes memory req, bytes32 key) = _buildTcbAttestationRequest(tcbInfoObj);
        bytes32 hash = sha256(bytes(tcbInfoObj.tcbInfoStr));
        attestationId = _attestTcb(req, hash, key);
    }

    /**
     * @notice Fetches the TCBInfo Issuer Chain
     * @return signingCert - DER encoded Intel TCB Signing Certificate
     * @return rootCert - DER encoded Intel SGX Root CA
     */
    function getTcbIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert) {
        signingCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
        rootCert = _onFetchDataFromResolver(Pcs.PCS_KEY(CA.ROOT, false), false);
    }

    /**
     * @notice attests collateral via the Resolver
     * @return attestationId
     */
    function _attestTcb(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        virtual
        returns (bytes32 attestationId)
    {
        (attestationId,) = resolver.attest(key, reqData, hash);
    }

    /**
     * @notice constructs the TcbInfo.json attestation data
     */
    function _buildTcbAttestationRequest(TcbInfoJsonObj calldata tcbInfoObj)
        private
        view
        returns (bytes memory reqData, bytes32 key)
    {
        TcbInfoBasic memory tcbInfo;
        (reqData, tcbInfo) = _buildAttestationData(tcbInfoObj.tcbInfoStr, tcbInfoObj.signature);
        key = FMSPC_TCB_KEY(uint8(tcbInfo.id), tcbInfo.fmspc, tcbInfo.version);
        if (block.timestamp < tcbInfo.issueDate || block.timestamp > tcbInfo.nextUpdate) {
            revert TCB_Expired();
        }
    }

    function _buildAttestationData(string memory tcbInfoStr, bytes memory signature)
        private
        view
        returns (bytes memory attestationData, TcbInfoBasic memory tcbInfo)
    {
        (, TCBLevelsObj[] memory tcbLevels) = FmspcTcbLib.parseTcbLevels(tcbInfoStr);
        tcbInfo = FmspcTcbLib.parseTcbString(tcbInfoStr);
        if (tcbInfo.version < 3) {
            attestationData = abi.encode(tcbInfo, tcbLevels, tcbInfoStr, signature);
        } else {
            TDXModule memory module;
            TDXModuleIdentity[] memory moduleIdentities;
            if (tcbInfo.id == TcbId.TDX) {
                (module, moduleIdentities) = FmspcTcbLib.parseTcbTdxModules(tcbInfoStr);
            }
            attestationData = abi.encode(tcbInfo, module, moduleIdentities, tcbLevels, tcbInfoStr, signature);
        }
    }

    function _validateTcbInfo(TcbInfoJsonObj calldata tcbInfoObj) private view {
        // Get TCB Signing Cert
        bytes memory signingDer = _fetchDataFromResolver(Pcs.PCS_KEY(CA.SIGNING, false), false);
       
        // Validate signature
        bool sigVerified = verifySignature(sha256(bytes(tcbInfoObj.tcbInfoStr)), tcbInfoObj.signature, signingDer);

        if (!sigVerified) {
            revert Invalid_TCB_Cert_Signature();
        }
    }
}

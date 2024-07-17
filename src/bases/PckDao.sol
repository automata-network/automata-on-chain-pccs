// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CA, AttestationRequestData, AttestationRequest} from "../Common.sol";
import {PCKHelper, X509CertObj} from "../helpers/PCKHelper.sol";
import {X509CRLHelper, X509CRLObj} from "../helpers/X509CRLHelper.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LibString} from "solady/utils/LibString.sol";

import {PcsDao} from "./PcsDao.sol";
import {DaoBase} from "./DaoBase.sol";
import {SigVerifyBase} from "./SigVerifyBase.sol";

/**
 * @title Intel PCK Certificate Data Access Object
 * @notice This contract is heavily inspired by Sections 4.2.2, 4.2.4 and 4.2.8 in the Intel SGX PCCS Design Guideline
 * https://download.01.org/intel-sgx/sgx-dcap/1.19/linux/docs/SGX_DCAP_Caching_Service_Design_Guide.pdf
 * @notice This contract is the combination of both PckDao and PlatformTcbsDao as described in section 4.2
 */
abstract contract PckDao is DaoBase, SigVerifyBase {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error Certificate_Revoked(uint256 serialNum);
    error Certificate_Expired();
    error Invalid_Issuer_Name();
    error Invalid_Subject_Name();
    error Expired_Certificates();
    error TCB_Mismatch();
    error Missing_Issuer();
    error Invalid_Signature();

    string constant PCK_PLATFORM_CA_COMMON_NAME = "Intel SGX PCK Platform CA";
    string constant PCK_PROCESSOR_CA_COMMON_NAME = "Intel SGX PCK Processor CA";
    string constant PCK_COMMON_NAME = "Intel SGX PCK Certificate";

    PcsDao public Pcs;
    PCKHelper public pckLib;
    X509CRLHelper public crlLib;

    /// mapping (keccak256(qeid ++ pceid) => Enumerable tcbm Set)
    /// tcbm is a 18-byte data which is a concatenation of PCK cpusvn (16 bytes) and pcesvn (2 bytes)
    mapping(bytes32 => EnumerableSet.Bytes32Set) private _tcbmHSets;

    /// @notice retrieves the attested TCBm from the registry
    /// key: keccak256(qeid ++ pceid ++ platformCpuSvn ++ platformPceSvn)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes18 tcbm
    mapping(bytes32 => bytes32) public tcbmAttestations;

    /// @notice retrieves the attested PCK Cert from the registry
    /// key: keccak256(qeid ++ pceid ++ tcbm)
    ///
    /// @notice the schema of the attested data is the following:
    /// - bytes pckCert
    mapping(bytes32 => bytes32) public pckCertAttestations;

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

    constructor(address _pcs, address _x509, address _crl) SigVerifyBase(_x509) {
        Pcs = PcsDao(_pcs);
        pckLib = PCKHelper(_x509);
        crlLib = X509CRLHelper(_crl);
    }

    /**
     * @notice Section 4.2.2 (getCert(qe_id, cpu_svn, pce_svn, pce_id))
     */
    function getCert(
        string calldata qeid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata pceid
    ) external view returns (bytes memory pckCert) {
        (bytes16 qeidBytes, bytes2 pceidBytes, bytes16 platformCpuSvnBytes, bytes2 platformPceSvnBytes,) =
            _parseStringInputs(qeid, pceid, platformCpuSvn, platformPceSvn, "");

        bytes32 tcbmAttestationId =
            tcbmAttestations[_getTcbmKey(qeidBytes, pceidBytes, platformCpuSvnBytes, platformPceSvnBytes)];
        bytes18 tcbmBytes = bytes18(getAttestedData(tcbmAttestationId));
        bytes32 attestationId = _getPckAttestationId(qeidBytes, pceidBytes, tcbmBytes);
        if (attestationId != bytes32(0)) {
            pckCert = getAttestedData(attestationId);
        }
    }

    function getCerts(string calldata qeid, string calldata pceid)
        external
        view
        returns (string[] memory tcbms, bytes[] memory pckCerts)
    {
        (bytes16 qeidBytes, bytes2 pceidBytes,,,) = _parseStringInputs(qeid, pceid, "", "", "");

        bytes32 k = keccak256(abi.encodePacked(qeidBytes, pceidBytes));
        uint256 n = _tcbmHSets[k].length();
        if (n > 0) {
            tcbms = new string[](n);
            pckCerts = new bytes[](n);
            for (uint256 i = 0; i < n; i++) {
                bytes18 tcbmBytes = bytes18(_tcbmHSets[k].at(i));
                tcbms[i] = LibString.toHexStringNoPrefix(abi.encodePacked(tcbmBytes));
                bytes32 attestationId = _getPckAttestationId(qeidBytes, pceidBytes, tcbmBytes);
                pckCerts[i] = getAttestedData(attestationId);
            }
        }
    }

    /**
     * @notice Modified from Section 4.2.8 (getPlatformTcbsById)
     * @dev For simplicity's sake, the contract currently requires all the necessary parameters
     * to return a single tcbm.
     */
    function getPlatformTcbByIdAndSvns(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn
    ) external view returns (string memory tcbm) {
        (bytes16 qeidBytes, bytes2 pceidBytes, bytes16 platformCpuSvnBytes, bytes2 platformPceSvnBytes,) =
            _parseStringInputs(qeid, pceid, platformCpuSvn, platformPceSvn, "");

        bytes32 attestationId = _getTcbmAttestationId(qeidBytes, pceidBytes, platformCpuSvnBytes, platformPceSvnBytes);
        if (attestationId != bytes32(0)) {
            tcbm = LibString.toHexStringNoPrefix(abi.encodePacked(bytes18(getAttestedData(attestationId))));
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
        (bytes16 qeidBytes, bytes2 pceidBytes,,, bytes18 tcbmBytes) = _parseStringInputs(qeid, pceid, "", "", tcbm);
        bytes32 hash = _validatePck(ca, cert, tcbmBytes, pceidBytes);
        AttestationRequest memory req = _buildPckCertAttestationRequest(qeidBytes, pceidBytes, tcbmBytes, cert);
        attestationId = _attestPck(req, hash);
        pckCertAttestations[keccak256(abi.encodePacked(qeidBytes, pceidBytes, tcbmBytes))] = attestationId;
        _upsertTcbm(qeidBytes, pceidBytes, tcbmBytes);
    }

    /// @dev currently missing strict TCB check on platformCpuSvn and platformPceSvn
    /// @dev is recommended to overwrite this method to implement TCB check
    function upsertPlatformTcbs(
        string calldata qeid,
        string calldata pceid,
        string calldata platformCpuSvn,
        string calldata platformPceSvn,
        string calldata tcbm
    ) external virtual returns (bytes32 attestationId) {
        (
            bytes16 qeidBytes,
            bytes2 pceidBytes,
            bytes16 platformCpuSvnBytes,
            bytes2 platformPceSvnBytes,
            bytes18 tcbmBytes
        ) = _parseStringInputs(qeid, pceid, platformCpuSvn, platformPceSvn, tcbm);

        bytes32 pckKey = keccak256(abi.encodePacked(qeidBytes, pceidBytes, tcbmBytes));
        bytes32 pckAttestationId = pckCertAttestations[pckKey];

        if (pckAttestationId == bytes32(0)) {
            revert Pck_Not_Found();
        }

        // parse PCK to check PCEID and tcbm
        bytes memory der = getAttestedData(pckAttestationId);
        X509CertObj memory pck = pckLib.parseX509DER(der);
        _validatePckTcb(pceidBytes, tcbmBytes, der, pck.extensionPtr);

        AttestationRequest memory req =
            _buildTcbmAttestationRequest(qeidBytes, pceidBytes, platformCpuSvnBytes, platformPceSvnBytes, tcbmBytes);
        attestationId = _attestTcbm(req);
        bytes32 tcbmKey = _getTcbmKey(qeidBytes, pceidBytes, platformCpuSvnBytes, platformPceSvnBytes);
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
        intermediateCert = getAttestedData(intermediateCertAttestationId);
        rootCert = getAttestedData(rootCertAttestationId);
    }

    /**
     * @dev call this method to check whether the provided pck certificate has been revoked
     */
    function _checkPckIsRevocable(CA ca, bytes memory pck) internal view pckCACheck(ca) returns (bool revocable) {
        uint256 serialNumber = pckLib.getSerialNumber(pck);
        bytes memory crlData = getAttestedData(Pcs.pcsCrlAttestations(ca));
        revocable = crlLib.serialNumberIsRevoked(serialNumber, crlData);
    }

    /**
     * @dev overwrite this method to define the schemaID for the attestation of PCK Certificates
     */
    function pckSchemaID() public view virtual returns (bytes32 PCK_SCHEMA_ID);

    function tcbmSchemaID() public view virtual returns (bytes32 TCBM_SCHEMA_ID);

    /**
     * @dev implement logic to validate and attest PCK Certificates
     * @param req structure as defined by EAS
     * https://github.com/ethereum-attestation-service/eas-contracts/blob/52af661748bde9b40ae782907702f885852bc149/contracts/IEAS.sol#L9C1-L23C2
     * @return attestationId
     */
    function _attestPck(AttestationRequest memory req, bytes32 hash) internal virtual returns (bytes32 attestationId);

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
    function _getPckAttestationId(bytes16 qeid, bytes2 pceid, bytes18 tcbm)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = pckCertAttestations[keccak256(abi.encodePacked(qeid, pceid, tcbm))];
    }

    /**
     * @notice computes the key that maps to the corresponding attestation ID
     */
    function _getTcbmAttestationId(bytes16 qeid, bytes2 pceid, bytes16 platformCpuSvn, bytes2 platformPceSvn)
        private
        view
        returns (bytes32 attestationId)
    {
        attestationId = tcbmAttestations[_getTcbmKey(qeid, pceid, platformCpuSvn, platformPceSvn)];
    }

    /**
     * @notice builds an EAS compliant attestation request
     */
    function _buildPckCertAttestationRequest(bytes16 qeid, bytes2 pceid, bytes18 tcbm, bytes calldata cert)
        private
        view
        returns (AttestationRequest memory req)
    {
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
        bytes16 qeid,
        bytes2 pceid,
        bytes16 platformCpuSvn,
        bytes2 platformPceSvn,
        bytes18 tcbm
    ) private view returns (AttestationRequest memory req) {
        bytes32 predecessorAttestationId = _getTcbmAttestationId(qeid, pceid, platformCpuSvn, platformPceSvn);
        AttestationRequestData memory reqData = AttestationRequestData({
            recipient: msg.sender,
            expirationTime: 0, // assign zero here because this has already been checked
            revocable: true,
            refUID: predecessorAttestationId,
            data: abi.encode(tcbm),
            value: 0
        });
        req = AttestationRequest({schema: tcbmSchemaID(), data: reqData});
    }

    function _getTcbmKey(bytes16 qeid, bytes2 pceid, bytes16 platformCpuSvn, bytes2 platformPceSvn)
        private
        pure
        returns (bytes32 key)
    {
        key = keccak256(abi.encodePacked(qeid, pceid, platformCpuSvn, platformPceSvn));
    }

    function _upsertTcbm(bytes16 qeid, bytes2 pceid, bytes18 tcbm) private {
        bytes32 k = keccak256(abi.encodePacked(qeid, pceid));
        if (!_tcbmHSets[k].contains(bytes32(tcbm))) {
            _tcbmHSets[k].add(bytes32(tcbm));
        }
    }

    function _validatePck(CA ca, bytes memory der, bytes18 tcbm, bytes2 pceid) private view returns (bytes32 hash) {
        // Step 1: Check whether the pck has expired
        bool notExpired = pckLib.certIsNotExpired(der);
        if (!notExpired) {
            revert Certificate_Expired();
        }

        X509CertObj memory pck = pckLib.parseX509DER(der);
        hash = keccak256(pck.tbs);

        // Step 2: Check Issuer and Subject names
        string memory expectedIssuer;
        if (ca == CA.PLATFORM) {
            expectedIssuer = PCK_PLATFORM_CA_COMMON_NAME;
        } else if (ca == CA.PROCESSOR) {
            expectedIssuer = PCK_PROCESSOR_CA_COMMON_NAME;
        }
        if (!LibString.eq(pck.issuerCommonName, expectedIssuer)) {
            revert Invalid_Issuer_Name();
        }
        if (!LibString.eq(pck.subjectCommonName, PCK_COMMON_NAME)) {
            revert Invalid_Subject_Name();
        }

        // Step 3: validate PCEID and TCBm
        _validatePckTcb(pceid, tcbm, der, pck.extensionPtr);

        // Step 4: Check whether the pck has been revoked
        bytes memory crlData = getAttestedData(Pcs.pcsCrlAttestations(ca));
        if (crlData.length > 0) {
            bool revocable = crlLib.serialNumberIsRevoked(pck.serialNumber, crlData);
            if (revocable) {
                revert Certificate_Revoked(pck.serialNumber);
            }
        }

        // Step 5: Check signature
        (bytes memory issuerCert,) = getPckCertChain(ca);
        if (issuerCert.length > 0) {
            bytes32 digest = sha256(pck.tbs);
            bool sigVerified = verifySignature(digest, pck.signature, issuerCert);
            if (!sigVerified) {
                revert Invalid_Signature();
            }
        } else {
            revert Missing_Issuer();
        }
    }

    function _validatePckTcb(bytes2 pceid, bytes18 tcbm, bytes memory der, uint256 pckExtensionPtr) private view {
        (uint16 pcesvn, uint8[] memory cpusvns,, bytes memory pceidBytes) =
            pckLib.parsePckExtension(der, pckExtensionPtr);
        bool pceidMatched = bytes2(pceidBytes) == pceid;
        bytes memory encodedPceSvn = _littleEndianEncode(abi.encodePacked(pcesvn));
        bytes memory encodedCpuSvn;
        for (uint256 i = 0; i < cpusvns.length; i++) {
            encodedCpuSvn = abi.encodePacked(encodedCpuSvn, cpusvns[i]);
        }
        bytes memory encodedTcbmBytes = abi.encodePacked(encodedCpuSvn, encodedPceSvn);
        bool tcbIsValid = tcbm == bytes18(encodedTcbmBytes);
        if (!pceidMatched || !tcbIsValid) {
            revert TCB_Mismatch();
        }
    }

    function _littleEndianEncode(bytes memory input) private pure returns (bytes memory encoded) {
        uint256 n = input.length;
        for (uint256 i = n; i > 0;) {
            encoded = abi.encodePacked(encoded, input[i - 1]);
            unchecked {
                i--;
            }
        }
    }

    function _parseStringInputs(
        string memory qeid,
        string memory pceid,
        string memory platformCpuSvn,
        string memory platformPceSvn,
        string memory tcbm
    )
        private
        pure
        returns (
            bytes16 qeidBytes,
            bytes2 pceidBytes,
            bytes16 platformCpuSvnBytes,
            bytes2 platformPceSvnBytes,
            bytes18 tcbmBytes
        )
    {
        if (bytes(qeid).length == 32) {
            qeidBytes = bytes16(uint128(_parseUintFromHex(qeid)));
        }
        if (bytes(pceid).length == 4) {
            pceidBytes = bytes2(uint16(_parseUintFromHex(pceid)));
        }
        if (bytes(platformCpuSvn).length == 32) {
            platformCpuSvnBytes = bytes16(uint128(_parseUintFromHex(platformCpuSvn)));
        }
        if (bytes(platformPceSvn).length == 4) {
            platformPceSvnBytes = bytes2(uint16(_parseUintFromHex(platformPceSvn)));
        }
        if (bytes(tcbm).length == 36) {
            tcbmBytes = bytes18(uint144(_parseUintFromHex(tcbm)));
        }
    }
}

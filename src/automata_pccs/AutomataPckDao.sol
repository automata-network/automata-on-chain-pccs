// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PckDao, AttestationRequest, PcsDao, X509CRLHelper} from "../bases/PckDao.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {AutomataDaoStorage} from "./shared/AutomataDaoStorage.sol";

contract AutomataPckDao is Ownable, PckDao {
    constructor(address _storage, address _p256, address _pcs, address _x509, address _crl)
        PckDao(_storage, _p256, _pcs, _x509, _crl)
    {
        _initializeOwner(msg.sender);
    }

    function updateDeps(address _pcs, address _x509, address _crl) external onlyOwner {
        Pcs = PcsDao(_pcs);
        x509 = _x509;
        crlLib = X509CRLHelper(_crl);
    }

    function pckSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function tcbmSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function _upsertTcbm(bytes16 qeid, bytes2 pceid, bytes18 tcbm) internal override {
        AutomataDaoStorage(address(resolver)).setTcbm(qeid, pceid, tcbm);
    }

    function _getAllTcbs(bytes16 qeidBytes, bytes2 pceidBytes)
        internal
        view
        override
        returns (bytes18[] memory tcbms)
    {
        tcbms = AutomataDaoStorage(address(resolver)).printTcbmSet(qeidBytes, pceidBytes);
    }

    function _setTcbrToTcbmMapping(bytes32 tcbMappingKey, bytes18 tcbmBytes) internal override {
        AutomataDaoStorage(address(resolver)).setTcbrMapping(tcbMappingKey, tcbmBytes);
    }

    function _tcbrToTcbmMapping(bytes32 tcbMappingKey) internal view override returns (bytes18 tcbm) {
        tcbm = AutomataDaoStorage(address(resolver)).getTcbm(tcbMappingKey);
    }
}

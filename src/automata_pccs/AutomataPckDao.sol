// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PckDao, PcsDao, X509CRLHelper, DaoBase} from "../bases/PckDao.sol";
import {AutomataDaoStorage} from "./shared/AutomataDaoStorage.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataPckDao is AutomataDaoBase, PckDao {
    constructor(address _storage, address _p256, address _pcs, address _x509, address _crl)
        PckDao(_storage, _p256, _pcs, _x509, _crl)
    {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
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

    function _storePckValidity(bytes32 key, uint64 notValidBefore, uint64 notValidAfter) internal override {
        bytes32 pckValidityKey = _computePckValidityKey(key);
        uint256 slot = (uint256(notValidBefore) << 64) | notValidAfter;
        resolver.attest(pckValidityKey, abi.encode(slot), bytes32(0));
    }

    function _loadPckValidity(bytes32 key) internal view override returns (uint64 notValidBefore, uint64 notValidAfter) {
        bytes32 pckValidityKey = _computePckValidityKey(key);
        bytes memory data = _fetchDataFromResolver(pckValidityKey, false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            notValidBefore = uint64(slot >> 64);
            notValidAfter = uint64(slot);
        }
    }

    function _computePckValidityKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "pckValidity"));
    }
}

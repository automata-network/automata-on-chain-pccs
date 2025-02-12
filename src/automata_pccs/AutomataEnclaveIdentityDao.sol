// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnclaveIdentityDao, PcsDao, DaoBase} from "../bases/EnclaveIdentityDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataEnclaveIdentityDao is AutomataDaoBase, EnclaveIdentityDao {
    constructor(address _storage, address _p256, address _pcs, address _enclaveIdentityHelper, address _x509Helper)
        EnclaveIdentityDao(_storage, _p256, _pcs, _enclaveIdentityHelper, _x509Helper)
    {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }

    function _storeIdentityContentHash(bytes32 identityKey, bytes32 contentHash) internal override {
        // write content hash to storage anyway regardless of whether it changes
        // it is still cheaper to directly write the unchanged non-zero values to the same slot
        // instead of, SLOAD-ing and comparing the values, then write to storage slot
        // this saves gas by skipping SLOAD
        bytes32 contentHashKey = _computeContentHashKey(identityKey);
        resolver.attest(contentHashKey, abi.encodePacked(contentHash), bytes32(0));
    }

    function _loadIdentityContentHash(bytes32 identityKey) internal view override returns (bytes32 contentHash) {
        bytes32 contentHashKey = _computeContentHashKey(identityKey);
        return bytes32(_fetchDataFromResolver(contentHashKey, false));
    }

    function _computeContentHashKey(bytes32 key) internal pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "identityContentHash"));
    }
}

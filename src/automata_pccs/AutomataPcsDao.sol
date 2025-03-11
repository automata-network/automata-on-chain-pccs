// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PcsDao, X509CRLHelper, DaoBase} from "../bases/PcsDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataPcsDao is AutomataDaoBase, PcsDao {
    constructor(address _storage, address _p256, address _x509, address _crl) PcsDao(_storage, _p256, _x509, _crl) {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }

    function _storePcsValidity(bytes32 key, uint64 notValidBefore, uint64 notValidAfter) internal override {
        bytes32 pcsValidityKey = _computePcsValidityKey(key);
        uint256 slot = (uint256(notValidBefore) << 64) | notValidAfter;
        resolver.attest(pcsValidityKey, abi.encode(slot), bytes32(0));
    }

    function _loadPcsValidity(bytes32 key)
        internal
        view
        override
        returns (uint64 notValidBefore, uint64 notValidAfter)
    {
        bytes32 pcsValidityKey = _computePcsValidityKey(key);
        bytes memory data = _fetchDataFromResolver(pcsValidityKey, false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            notValidBefore = uint64(slot >> 64);
            notValidAfter = uint64(slot);
        }
    }

    function _computePcsValidityKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "pcsValidity"));
    }
}

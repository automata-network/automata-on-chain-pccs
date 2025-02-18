// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnclaveIdentityDao, PcsDao, DaoBase} from "../bases/EnclaveIdentityDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataEnclaveIdentityDao is AutomataDaoBase, EnclaveIdentityDao {
    constructor(address _storage, address _p256, address _pcs, address _enclaveIdentityHelper, address _x509Helper, address _crl)
        EnclaveIdentityDao(_storage, _p256, _pcs, _enclaveIdentityHelper, _x509Helper, _crl)
    {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }

    function _storeEnclaveIdentityIssueEvaluation(bytes32 key, uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber) internal override {
        bytes32 tcbIssueEvaluationKey = _computeIssueEvaluationKey(key);
        uint256 slot = (uint256(issueDateTimestamp) << 192) | (uint256(nextUpdateTimestamp) << 128) | evaluationDataNumber;
        resolver.attest(tcbIssueEvaluationKey, abi.encode(slot), bytes32(0));
    }

    function _loadEnclaveIdentityIssueEvaluation(bytes32 key) internal view override returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber) {
        bytes32 tcbIssueEvaluationKey = _computeIssueEvaluationKey(key);
        bytes memory data = _fetchDataFromResolver(tcbIssueEvaluationKey, false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            issueDateTimestamp = uint64(slot >> 192);
            nextUpdateTimestamp = uint64(slot >> 128);
            evaluationDataNumber = uint32(slot);
        }
    }

    function _computeIssueEvaluationKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "identityIssueEvaluation"));
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

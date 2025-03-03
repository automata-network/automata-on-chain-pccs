// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao, PcsDao, DaoBase} from "../bases/FmspcTcbDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataFmspcTcbDao is AutomataDaoBase, FmspcTcbDao {
    constructor(address _storage, address _p256, address _pcs, address _fmspcHelper, address _x509Helper, address _crl)
        FmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper, _crl)
    {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }

    /// @dev submit tcb timestamps and evaluation data number as a separate attestation
    /// @dev issueDateTimestamp (64 bytes) | nextUpdateTimestamp (64 bytes) | evaluationDataNumber (128 bytes)
    /// TEMP: it is not the most efficient approach, since it's storing duplicate data
    /// @dev if i could extract the required info directly from the attestation,
    /// this method will no longer be needed
    /// @dev this is a good TODO for future optimization
    function _storeTcbInfoIssueEvaluation(bytes32 tcbKey, uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber) internal override {
        bytes32 tcbIssueEvaluationKey = _computeTcbIssueEvaluationKey(tcbKey);
        uint256 slot = (uint256(issueDateTimestamp) << 192) | (uint256(nextUpdateTimestamp) << 128) | evaluationDataNumber;
        resolver.attest(tcbIssueEvaluationKey, abi.encode(slot), bytes32(0));
    }

    /// TEMP it just reads from a separate attestation for now
    /// @dev we will have to come up with hacky low-level storage reads
    function _loadTcbInfoIssueEvaluation(bytes32 tcbKey) internal view override returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp, uint32 evaluationDataNumber) {
        bytes32 tcbIssueEvaluationKey = _computeTcbIssueEvaluationKey(tcbKey);
        bytes memory data = _fetchDataFromResolver(tcbIssueEvaluationKey, false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            issueDateTimestamp = uint64(slot >> 192);
            nextUpdateTimestamp = uint64(slot >> 128);
            evaluationDataNumber = uint32(slot);
        }
    }

    function _computeTcbIssueEvaluationKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbIssueEvaluation"));
    }

    function _storeFmspcTcbContentHash(bytes32 tcbKey, bytes32 contentHash) internal override {
        // write content hash to storage anyway regardless of whether it changes
        // it is still cheaper to directly write the unchanged non-zero values to the same slot
        // instead of, SLOAD-ing and comparing the values, then write to storage slot
        // this saves gas by skipping SLOAD
        bytes32 contentHashKey = _computeContentHashKey(tcbKey);
        resolver.attest(contentHashKey, abi.encodePacked(contentHash), bytes32(0));
    }

    function _loadFmspcTcbContentHash(bytes32 tcbKey) internal view override returns (bytes32 contentHash) {
        bytes32 contentHashKey = _computeContentHashKey(tcbKey);
        return bytes32(_fetchDataFromResolver(contentHashKey, false));
    }

    function _computeContentHashKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "fmspcTcbContentHash"));
    }
}

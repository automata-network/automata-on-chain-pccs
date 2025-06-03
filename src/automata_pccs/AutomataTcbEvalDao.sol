// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TcbEvalDao, PcsDao, DaoBase} from "../bases/TcbEvalDao.sol";
import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";

contract AutomataTcbEvalDao is AutomataDaoBase, TcbEvalDao {
    constructor(
        address _storage,
        address _p256,
        address _pcs,
        address _tcbEvalHelper,
        address _x509Helper,
        address _crl
    ) TcbEvalDao(_storage, _p256, _pcs, _tcbEvalHelper, _x509Helper, _crl) {}

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override(AutomataDaoBase, DaoBase)
        returns (bytes memory data)
    {
        data = super._onFetchDataFromResolver(key, hash);
    }

    /// @dev submit TCB evaluation data timestamps as a separate attestation
    /// @dev issueDateTimestamp (64 bytes) | nextUpdateTimestamp (64 bytes) | padding (128 bytes)
    /// TEMP: it is not the most efficient approach, since it's storing duplicate data
    /// @dev if i could extract the required info directly from the attestation,
    /// this method will no longer be needed
    /// @dev this is a good TODO for future optimization
    function _storeTcbEvalIssueData(bytes32 tcbEvalKey, uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
        internal
        override
    {
        bytes32 tcbEvalIssueKey = _computeTcbEvalIssueKey(tcbEvalKey);
        uint256 slot = (uint256(issueDateTimestamp) << 192) | (uint256(nextUpdateTimestamp) << 128);
        resolver.attest(tcbEvalIssueKey, abi.encode(slot), bytes32(0));
    }

    /// TEMP it just reads from a separate attestation for now
    /// @dev we will have to come up with hacky low-level storage reads
    function _loadTcbEvalIssueData(bytes32 tcbEvalKey)
        internal
        view
        override
        returns (uint64 issueDateTimestamp, uint64 nextUpdateTimestamp)
    {
        bytes32 tcbEvalIssueKey = _computeTcbEvalIssueKey(tcbEvalKey);
        bytes memory data = _fetchDataFromResolver(tcbEvalIssueKey, false);
        if (data.length > 0) {
            (uint256 slot) = abi.decode(data, (uint256));
            issueDateTimestamp = uint64(slot >> 192);
            nextUpdateTimestamp = uint64(slot >> 128);
        }
    }

    function _computeTcbEvalIssueKey(bytes32 key) private pure returns (bytes32 ret) {
        ret = keccak256(abi.encodePacked(key, "tcbEvalIssue"));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "solady/auth/Ownable.sol";

contract AutomataDaoStorage is Ownable {
    mapping(address => bool) _authorized;

    mapping(bytes32 attId => bytes attData) _pccsData;

    modifier onlyAuthorized(address dao) {
        require(_authorized[dao], "Unauthorized caller");
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function updateDao(address _pcsDao, address _pckDao, address _fmspcTcbDao, address _enclaveIdDao)
        external
        onlyOwner
    {
        _updateDao(_pcsDao, _pckDao, _fmspcTcbDao, _enclaveIdDao);
    }

    function revokeDao(address revoked) external onlyOwner {
        _authorized[revoked] = false;
    }

    function writeToPccs(bytes32 attId, bytes memory attData) external onlyAuthorized(msg.sender) {
        _pccsData[attId] = attData;
    }

    function deleteData(bytes32 attId) external onlyAuthorized(msg.sender) {
        delete _pccsData[attId];
    }

    function readPccs(bytes32 attId) external view returns (bytes memory attData) {
        attData = _pccsData[attId];
    }

    function _updateDao(address _pcsDao, address _pckDao, address _fmspcTcbDao, address _enclaveIdDao) private {
        _authorized[_pcsDao] = true;
        _authorized[_pckDao] = true;
        _authorized[_fmspcTcbDao] = true;
        _authorized[_enclaveIdDao] = true;
    }
}

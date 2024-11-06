// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IDaoAttestationResolver} from "../../interfaces/IDaoAttestationResolver.sol";
import {AutomataTCBManager, EnumerableSet} from "./AutomataTCBManager.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract AutomataDaoStorage is AutomataTCBManager, IDaoAttestationResolver, Pausable, Ownable {
    mapping(address => bool) _authorized_writers;
    mapping(address => bool) _authorized_readers;
    mapping(bytes32 attId => bytes collateral) _db;

    modifier onlyDao(address dao) {
        require(_authorized_writers[dao], "FORBIDDEN");
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);

        // adding address(0) as an authorized_reader to allow eth_call
        _authorized_readers[address(0)] = true;
    }

    function isAuthorizedCaller(address caller) external view returns (bool) {
        return _authorized_readers[caller];
    }

    function pauseCallerRestriction() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            _pause();
        }
    }

    function updateDao(address _pcsDao, address _pckDao, address _fmspcTcbDao, address _enclaveIdDao)
        external
        onlyOwner
    {
        _updateDao(_pcsDao, _pckDao, _fmspcTcbDao, _enclaveIdDao);
    }

    function revokeDao(address revoked) external onlyOwner {
        _authorized_writers[revoked] = false;
    }

    function collateralPointer(bytes32 key) external pure override returns (bytes32 collateralAttId) {
        collateralAttId = key;
    }

    function collateralHashPointer(bytes32 key) external pure override returns (bytes32 collateralHashAttId) {
        collateralHashAttId = bytes32(uint256(key) + 1);
    }

    function readAttestation(bytes32 attestationId)
        external
        view
        override
        onlyDao(msg.sender)
        returns (bytes memory attData)
    {
        attData = _db[attestationId];
    }

    /**
     * @notice In AutomataDaoStorage, we will simply assign the key as the attestationid of the collateral
     * @notice whereas the value (key + 1) will be the attestation id to the hash.
     * (It's stupid I know, i will circle back when i come up with
     * a better approach on storing collateral hashes)
     */
    function attest(bytes32 key, bytes calldata attData, bytes32 attDataHash)
        external
        override
        onlyDao(msg.sender)
        returns (bytes32 attestationId, bytes32 hashAttestationid)
    {
        attestationId = key;
        hashAttestationid = bytes32(uint256(key) + 1);

        _db[attestationId] = attData;
        _db[hashAttestationid] = abi.encodePacked(attDataHash);
    }

    function _updateDao(address _pcsDao, address _pckDao, address _fmspcTcbDao, address _enclaveIdDao) private {
        _authorized_writers[_pcsDao] = true;
        _authorized_writers[_pckDao] = true;
        _authorized_writers[_fmspcTcbDao] = true;
        _authorized_writers[_enclaveIdDao] = true;
    }

    /// TCB Management
    using EnumerableSet for EnumerableSet.Bytes32Set;

    function setTcbm(bytes16 qeid, bytes2 pceid, bytes18 tcbm) external onlyDao(msg.sender) {
        bytes32 k = keccak256(abi.encodePacked(qeid, pceid));
        if (!_tcbmSet[k].contains(bytes32(tcbm))) {
            _tcbmSet[k].add(bytes32(tcbm));
        }
    }

    function printTcbmSet(bytes16 qeid, bytes2 pceid) external view returns (bytes18[] memory set) {
        bytes32 k = keccak256(abi.encodePacked(qeid, pceid));
        uint256 n = _tcbmSet[k].length();
        set = new bytes18[](n);
        for (uint256 i = 0; i < n;) {
            set[i] = bytes18(_tcbmSet[k].at(i));
            unchecked {
                i++;
            }
        }
    }

    function setTcbrMapping(bytes32 rawTcbKey, bytes18 tcbm) external onlyDao(msg.sender) {
        _tcbMapping[rawTcbKey] = tcbm;
    }

    function getTcbm(bytes32 rawTcbKey) external view onlyDao(msg.sender) returns (bytes18 tcbm) {
        tcbm = _tcbMapping[rawTcbKey];
    }
}

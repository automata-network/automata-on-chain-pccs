// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";
import {FmspcTcbDao, AttestationRequest, PcsDao} from "../bases/FmspcTcbDao.sol";

import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataFmspcTcbDao is Ownable, AutomataDaoBase, FmspcTcbDao {
    constructor(address _storage, address _pcs, address _fmspcHelper, address _x509Helper)
        AutomataDaoBase(_storage)
        FmspcTcbDao(_pcs, _fmspcHelper, _x509Helper)
    {
        _initializeOwner(msg.sender);
    }

    function setPcs(address _pcs) external onlyOwner {
        Pcs = PcsDao(_pcs);
    }

    function fmpscTcbV2SchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function fmpscTcbV3SchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function _attestTcb(AttestationRequest memory req, bytes32 hash)
        internal
        override
        returns (bytes32 attestationId)
    {
        // delete the predecessor if replacing
        _deletePredecessor(req.data.refUID);
        _attestCollateral(hash, req.data.data);
        attestationId = hash;
    }
}

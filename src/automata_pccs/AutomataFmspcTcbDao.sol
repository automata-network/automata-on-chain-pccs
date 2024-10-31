// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FmspcTcbDao, AttestationRequest, PcsDao} from "../bases/FmspcTcbDao.sol";

import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataFmspcTcbDao is Ownable, FmspcTcbDao {
    constructor(address _storage, address _p256, address _pcs, address _fmspcHelper, address _x509Helper)
        FmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper)
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
}

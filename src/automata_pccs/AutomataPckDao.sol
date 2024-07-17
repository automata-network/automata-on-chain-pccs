// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";
import {PckDao, AttestationRequest, PcsDao, X509CRLHelper} from "../bases/PckDao.sol";

import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataPckDao is Ownable, AutomataDaoBase, PckDao {
    constructor(address _storage, address _pcs, address _x509, address _crl)
        AutomataDaoBase(_storage)
        PckDao(_pcs, _x509, _crl)
    {
        _initializeOwner(msg.sender);
    }

    function updateDeps(address _pcs, address _x509, address _crl) external onlyOwner {
        Pcs = PcsDao(_pcs);
        x509 = _x509;
        crlLib = X509CRLHelper(_crl);
    }

    function pckSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function tcbmSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function _attestPck(AttestationRequest memory req, bytes32 hash)
        internal
        override
        returns (bytes32 attestationId)
    {
        // delete the predecessor if replacing
        _deletePredecessor(req.data.refUID);
        _attestCollateral(hash, req.data.data);
        attestationId = hash;
    }

    function _attestTcbm(AttestationRequest memory req) internal override returns (bytes32 attestationId) {
        // delete the predecessor if replacing
        _deletePredecessor(req.data.refUID);

        bytes32 hash = keccak256(req.data.data);
        _attestCollateral(hash, req.data.data);
        attestationId = hash;
    }
}

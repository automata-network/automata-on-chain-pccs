// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomataDaoBase} from "./shared/AutomataDaoBase.sol";
import {PcsDao, AttestationRequest, X509CRLHelper} from "../bases/PcsDao.sol";

import {Ownable} from "solady/auth/Ownable.sol";

contract AutomataPcsDao is AutomataDaoBase, PcsDao, Ownable {
    constructor(address _storage, address _x509, address _crl) AutomataDaoBase(_storage) PcsDao(_x509, _crl) {
        _initializeOwner(msg.sender);
    }

    function updateDeps(address _x509, address _crl) external onlyOwner {
        x509 = _x509;
        crlLib = X509CRLHelper(_crl);
    }

    function pcsCertSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function pcsCrlSchemaID() public pure override returns (bytes32) {
        // NOT-APPLICABLE FOR OUR USE CASE
        // but this is required by most attestation services, such as EAS, Verax etc
        return bytes32(0);
    }

    function _attestPcs(AttestationRequest memory req, bytes32 hash)
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

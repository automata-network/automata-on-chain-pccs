// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

import {AutomataEnclaveIdentityDao} from "../AutomataEnclaveIdentityDao.sol";
import {IdentityObj} from "../../helpers/EnclaveIdentityHelper.sol";

contract AutomataEnclaveIdentityDaoVersioned is AutomataEnclaveIdentityDao, OwnableRoles {
    uint32 public immutable TCB_EVALUATION_NUMBER;
    uint256 public constant ATTESTER_ROLE = _ROLE_0;

    error Invalid_Tcb_Evaluation_Data_Number();
    
    constructor(
        address _storage,
        address _p256,
        address _pcs,
        address _enclaveIdentityHelper,
        address _x509Helper,
        address _crl,
        address _owner,
        uint32 _tcbEvaluationNumber
    ) AutomataEnclaveIdentityDao(_storage, _p256, _pcs, _enclaveIdentityHelper, _x509Helper, _crl) {
        _initializeOwner(_owner);
        TCB_EVALUATION_NUMBER = _tcbEvaluationNumber;
    }

    function ENCLAVE_ID_KEY(uint256 id, uint256 version) public view override returns (bytes32 key) {
        key = keccak256(abi.encodePacked(ENCLAVE_ID_MAGIC, id, version, TCB_EVALUATION_NUMBER));
    }

    function _checkTcbEvaluationData(bytes32 key, IdentityObj memory identity) internal view override {
        (uint64 existingIssueDateTimestamp,,) =
            _loadEnclaveIdentityIssueEvaluation(key);
        bool outOfDate = existingIssueDateTimestamp >= identity.issueDateTimestamp;
        bool mismatchTcbEvaludationDataNumber = identity.tcbEvaluationDataNumber != TCB_EVALUATION_NUMBER;
        if (outOfDate) {
            revert Enclave_Id_Out_Of_Date();
        }
        if (mismatchTcbEvaludationDataNumber) {
            revert Invalid_Tcb_Evaluation_Data_Number();
        }
    }

    function _attestEnclaveIdentity(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        override
        onlyRoles(ATTESTER_ROLE)
        returns (bytes32 attestationId)
    {
        attestationId = super._attestEnclaveIdentity(reqData, hash, key);
    }
}

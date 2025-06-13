// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {AutomataFmspcTcbDao} from "../AutomataFmspcTcbDao.sol";
import {TcbInfoBasic} from "../../helpers/FmspcTcbHelper.sol";

contract AutomataFmspcTcbDaoVersioned is AutomataFmspcTcbDao, OwnableRoles {
    uint32 public immutable TCB_EVALUATION_NUMBER;
    uint256 public constant ATTESTER_ROLE = _ROLE_0;

    error Invalid_Tcb_Evaluation_Data_Number();

    constructor(
        address _storage,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _x509Helper,
        address _crl,
        address _owner,
        uint32 _tcbEvaluationNumber
    ) AutomataFmspcTcbDao(_storage, _p256, _pcs, _fmspcHelper, _x509Helper, _crl) {
        _initializeOwner(_owner);
        TCB_EVALUATION_NUMBER = _tcbEvaluationNumber;
    }

    function FMSPC_TCB_KEY(uint8 tcbType, bytes6 fmspc, uint32 version)
        public
        view
        override
        returns (bytes32 key)
    {
        key = keccak256(abi.encodePacked(FMSPC_TCB_MAGIC, tcbType, fmspc, version, TCB_EVALUATION_NUMBER));
    }

    function _checkTcbEvaluationData(bytes32 key, TcbInfoBasic memory tcbInfo) internal view override {
        (uint64 existingIssueDate,, /*uint32 existingEvaluationDataNumber*/) = _loadTcbInfoIssueEvaluation(key);

        if (existingIssueDate > 0) {
            // New collateral must have a strictly newer issue date than the existing one.
            if (tcbInfo.issueDate <= existingIssueDate) {
                revert TCB_Out_Of_Date();
            }
        }

        // New collateral's TCB evaluation data number must match the configured one for this versioned DAO.
        if (tcbInfo.evaluationDataNumber != TCB_EVALUATION_NUMBER) {
            revert Invalid_Tcb_Evaluation_Data_Number();
        }
    }

    function _attestTcb(bytes memory reqData, bytes32 hash, bytes32 key)
        internal
        override
        onlyRoles(ATTESTER_ROLE)
        returns (bytes32 attestationId)
    {
        attestationId = super._attestTcb(reqData, hash, key);
    }
}

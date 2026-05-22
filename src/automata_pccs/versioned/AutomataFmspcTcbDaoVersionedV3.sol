// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {FmspcTcbDaoV3} from "../../bases/FmspcTcbDaoV3.sol";
import {AutomataDaoStorageV2} from "../shared/AutomataDaoStorageV2.sol";
import {TcbInfoBasic} from "../../helpers/FmspcTcbHelper.sol";

/**
 * @title AutomataFmspcTcbDaoVersionedV3
 * @notice Versioned wrapper around FmspcTcbDaoV3. Pins one TCB_EVALUATION_NUMBER per deployment
 * and gates async-upsert entry points to the ATTESTER role. Layout mirrors
 * AutomataFmspcTcbDaoVersionedV2 so the PCCSRouter / IVersionedDao interface check works.
 */
contract AutomataFmspcTcbDaoVersionedV3 is FmspcTcbDaoV3, OwnableRoles {
    uint32 public immutable TCB_EVALUATION_NUMBER;
    uint256 public constant ATTESTER_ROLE = _ROLE_0;

    error Invalid_Tcb_Evaluation_Data_Number();
    error Unauthorized_Caller(address caller);

    constructor(
        address _storage,
        address _p256,
        address _pcs,
        address _fmspcHelper,
        address _fmspcHelperV2,
        address _fmspcHelperV3,
        address _x509Helper,
        address _crl,
        address _owner,
        uint32 _tcbEvaluationNumber
    )
        FmspcTcbDaoV3(
            _storage,
            _p256,
            _pcs,
            _fmspcHelper,
            _fmspcHelperV2,
            _fmspcHelperV3,
            _x509Helper,
            _crl
        )
    {
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

        if (existingIssueDate > 0 && tcbInfo.issueDate <= existingIssueDate) {
            revert TCB_Out_Of_Date();
        }

        if (tcbInfo.evaluationDataNumber != TCB_EVALUATION_NUMBER) {
            revert Invalid_Tcb_Evaluation_Data_Number();
        }
    }

    function _onFetchDataFromResolver(bytes32 key, bool hash)
        internal
        view
        override
        returns (bytes memory data)
    {
        if (_callerIsAuthorized()) {
            if (!hash) {
                data = _loadAsyncFinalPayload(key);
            }
            if (data.length == 0) {
                data = super._onFetchDataFromResolver(key, hash);
            }
        } else {
            revert Unauthorized_Caller(msg.sender);
        }
    }

    function _authorizeAsyncUpsert() internal view override onlyRoles(ATTESTER_ROLE) {}

    function _callerIsAuthorized() private view returns (bool authorized) {
        AutomataDaoStorageV2 automataStorage = AutomataDaoStorageV2(address(resolver));
        authorized = automataStorage.paused() || automataStorage.isAuthorizedCaller(msg.sender);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {FmspcTcbDaoV2} from "../../bases/FmspcTcbDaoV2.sol";
import {PcsDao} from "../../bases/PcsDao.sol";
import {AutomataDaoStorageV2} from "../shared/AutomataDaoStorageV2.sol";
import {IPccsDependencyConfig} from "../shared/PccsDependencyConfig.sol";
import {TcbInfoBasic} from "../../helpers/FmspcTcbHelper.sol";

contract AutomataFmspcTcbDaoVersionedV2 is FmspcTcbDaoV2, OwnableRoles {
    uint32 public immutable TCB_EVALUATION_NUMBER;
    uint256 public constant ATTESTER_ROLE = _ROLE_0;
    address private immutable _dependencyConfig;

    error Invalid_Tcb_Evaluation_Data_Number();
    error Unauthorized_Caller(address caller);

    constructor(
        address _storage,
        address _p256,
        address _dependencyConfigAddress,
        address _fmspcHelper,
        address _fmspcHelperV2,
        address _x509Helper,
        address _owner,
        uint32 _tcbEvaluationNumber
    )
        FmspcTcbDaoV2(
            _storage,
            _p256,
            IPccsDependencyConfig(_dependencyConfigAddress).pcsDao(),
            _fmspcHelper,
            _fmspcHelperV2,
            _x509Helper,
            IPccsDependencyConfig(_dependencyConfigAddress).crlHelper()
        )
    {
        _dependencyConfig = _dependencyConfigAddress;
        _initializeOwner(_owner);
        TCB_EVALUATION_NUMBER = _tcbEvaluationNumber;
    }

    function _pcsDao() internal view override returns (PcsDao) {
        return PcsDao(_dependencyAddress(0xcb625f04));
    }

    function _crlHelperAddress() internal view override returns (address) {
        return _dependencyAddress(0xabfbdb48);
    }

    function _dependencyAddress(bytes4 selector) private view returns (address result) {
        address config = _dependencyConfig;
        assembly ("memory-safe") {
            mstore(0x00, selector)
            if iszero(staticcall(gas(), config, 0x00, 0x04, 0x00, 0x20)) { revert(0x00, 0x00) }
            result := mload(0x00)
        }
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

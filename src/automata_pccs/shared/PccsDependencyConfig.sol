// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "solady/auth/Ownable.sol";

interface IPccsDependencyConfig {
    function pcsDao() external view returns (address);

    function crlHelper() external view returns (address);
}

/**
 * @notice Shared, timelocked configuration for the PCS DAO and CRL helper.
 * @dev New PCCS DAOs read both addresses from this contract so the pair changes
 * atomically and cannot drift between independently configured consumers.
 */
contract PccsDependencyConfig is IPccsDependencyConfig, Ownable {
    uint64 public constant CONFIG_DELAY = 3 hours;

    enum ConfigState {
        Uninitialized,
        Active,
        Pending,
        Ready
    }

    address public override pcsDao;
    address public override crlHelper;

    address public pendingPcsDao;
    address public pendingCrlHelper;
    uint64 public pendingExecutableAt;

    error Already_Initialized();
    error Not_Initialized();
    error Invalid_Config_Address(address target);
    error Invalid_Pcs_Crl_Binding(address pcs, address expectedCrl, address actualCrl);
    error Pending_Config_Exists();
    error No_Pending_Config();
    error Config_Not_Ready(uint64 executableAt);

    event DependencyConfigInitialized(address indexed pcsDao, address indexed crlHelper);
    event DependencyConfigScheduled(
        address indexed oldPcsDao,
        address indexed oldCrlHelper,
        address indexed newPcsDao,
        address newCrlHelper,
        uint64 executableAt
    );
    event DependencyConfigExecuted(
        address indexed oldPcsDao,
        address indexed oldCrlHelper,
        address indexed newPcsDao,
        address newCrlHelper
    );
    event DependencyConfigCancelled(address indexed pendingPcsDao, address indexed pendingCrlHelper);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    /**
     * @notice Sets the first live dependency pair before any consumer is activated.
     * @dev Deployment scripts must initialize, validate, and authorize the new
     * stack before exposing it through the Router. Every later change is delayed.
     */
    function initialize(address initialPcsDao, address initialCrlHelper) external onlyOwner {
        if (pcsDao != address(0) || crlHelper != address(0)) revert Already_Initialized();
        _validateConfig(initialPcsDao, initialCrlHelper);

        pcsDao = initialPcsDao;
        crlHelper = initialCrlHelper;
        _requirePcsCrlBinding(initialPcsDao, initialCrlHelper);

        emit DependencyConfigInitialized(initialPcsDao, initialCrlHelper);
    }

    function scheduleDependencyConfig(address newPcsDao, address newCrlHelper) external onlyOwner {
        if (pcsDao == address(0)) revert Not_Initialized();
        if (pendingExecutableAt != 0) revert Pending_Config_Exists();
        _validateConfig(newPcsDao, newCrlHelper);

        uint64 executableAt = uint64(block.timestamp + CONFIG_DELAY);
        pendingPcsDao = newPcsDao;
        pendingCrlHelper = newCrlHelper;
        pendingExecutableAt = executableAt;

        emit DependencyConfigScheduled(pcsDao, crlHelper, newPcsDao, newCrlHelper, executableAt);
    }

    /**
     * @notice Executes exactly the owner-scheduled pair after the delay.
     * @dev Execution is permissionless; the caller cannot alter the stored pair.
     */
    function executeDependencyConfig() external {
        uint64 executableAt = pendingExecutableAt;
        if (executableAt == 0) revert No_Pending_Config();
        if (block.timestamp < executableAt) revert Config_Not_Ready(executableAt);

        address oldPcsDao = pcsDao;
        address oldCrlHelper = crlHelper;
        address newPcsDao = pendingPcsDao;
        address newCrlHelper = pendingCrlHelper;

        pcsDao = newPcsDao;
        crlHelper = newCrlHelper;
        _clearPendingConfig();

        // Validate after applying the pair because a PCS implementation may
        // itself resolve crlLib() dynamically through this configuration.
        _requirePcsCrlBinding(newPcsDao, newCrlHelper);

        emit DependencyConfigExecuted(oldPcsDao, oldCrlHelper, newPcsDao, newCrlHelper);
    }

    function cancelDependencyConfig() external onlyOwner {
        if (pendingExecutableAt == 0) revert No_Pending_Config();

        address cancelledPcsDao = pendingPcsDao;
        address cancelledCrlHelper = pendingCrlHelper;
        _clearPendingConfig();

        emit DependencyConfigCancelled(cancelledPcsDao, cancelledCrlHelper);
    }

    function dependencyConfigState() external view returns (ConfigState state) {
        if (pcsDao == address(0)) return ConfigState.Uninitialized;
        if (pendingExecutableAt == 0) return ConfigState.Active;
        if (block.timestamp < pendingExecutableAt) return ConfigState.Pending;
        return ConfigState.Ready;
    }

    function _clearPendingConfig() private {
        pendingPcsDao = address(0);
        pendingCrlHelper = address(0);
        pendingExecutableAt = 0;
    }

    function _validateConfig(address newPcsDao, address newCrlHelper) private view {
        if (newPcsDao.code.length == 0) revert Invalid_Config_Address(newPcsDao);
        if (newCrlHelper.code.length == 0) revert Invalid_Config_Address(newCrlHelper);
    }

    function _requirePcsCrlBinding(address configuredPcsDao, address configuredCrlHelper) private view {
        (bool success, bytes memory result) = configuredPcsDao.staticcall(abi.encodeWithSignature("crlLib()"));
        address actualCrlHelper;
        if (success && result.length == 32) {
            actualCrlHelper = abi.decode(result, (address));
        }
        if (actualCrlHelper != configuredCrlHelper) {
            revert Invalid_Pcs_Crl_Binding(configuredPcsDao, configuredCrlHelper, actualCrlHelper);
        }
    }
}

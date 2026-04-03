// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICollateralVersioning {
    event CollateralVersionBumped(bytes32 indexed key, uint256 newVersion, uint256 timestamp);

    function collateralVersion(bytes32 key) external view returns (uint256 version);

    function hasChanged(bytes32 key, uint256 sinceVersion)
        external
        view
        returns (bool changed, uint256 currentVersion);
}

abstract contract CollateralVersioningMixin is ICollateralVersioning {
    mapping(bytes32 => uint256) private _versions;

    function collateralVersion(bytes32 key) external view override returns (uint256 version) {
        version = _versions[key];
    }

    function hasChanged(bytes32 key, uint256 sinceVersion)
        external
        view
        override
        returns (bool changed, uint256 currentVersion)
    {
        currentVersion = _versions[key];
        changed = currentVersion > sinceVersion;
    }

    function _bumpVersion(bytes32 key) internal {
        uint256 newVersion;
        unchecked {
            newVersion = _versions[key] + 1;
        }
        _versions[key] = newVersion;
        emit CollateralVersionBumped(key, newVersion, block.timestamp);
    }
}

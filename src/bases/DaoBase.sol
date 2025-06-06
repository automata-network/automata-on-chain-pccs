// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IDaoAttestationResolver.sol";

/**
 * @title Common Data Access Object base contract
 * @notice This contract provides the generic API methods to fetch collateral data
 * and its hashes from the Resolver
 */
abstract contract DaoBase {
    IDaoAttestationResolver public immutable resolver;

    // 72bd8361
    error Duplicate_Collateral();

    constructor(address _resolver) {
        resolver = IDaoAttestationResolver(_resolver);
    }

    /**
     * @dev must override this method to fetch the validity timestamp range for the specified collateral
     * @param key - mapped to a collateral as defined by individual data access objects (DAOs)
     * @return the timestamp that the collateral is being issued
     * @return the timestamp that the collateral expires and must be re-issued
     */
    function getCollateralValidity(bytes32 key) external view virtual returns (uint64, uint64);

    /**
     * @notice getter logic to retrieve attested data from the Resolver
     * @param key - mapped to a collateral as defined by individual data access objects (DAOs)
     */
    function getAttestedData(bytes32 key) external view returns (bytes memory attestationData) {
        // invoke _onFetchDataFromResolver() here to invoke additional logic
        attestationData = _onFetchDataFromResolver(key, false);
    }

    /**
     * @notice fetches the hash of a collateral (e.g. X509 Cert, TCBInfo JSON etc) from the attestation registry
     */
    function getCollateralHash(bytes32 key) external view returns (bytes32 collateralHash) {
        bytes memory attestationData = _fetchDataFromResolver(key, true);
        collateralHash = abi.decode(attestationData, (bytes32));
    }

    /**
     * @notice the default internal method to be called directly by the DAO
     * @notice ideally this is called to fetch a "signer" collateral such as a Signing
     * Certificate to validate a new collateral that is being upserted
     * @notice there should NOT be additional logic in place other than reading collaterals
     */
    function _fetchDataFromResolver(bytes32 key, bool hash) internal view returns (bytes memory) {
        bytes32 attestationId;
        if (hash) {
            attestationId = resolver.collateralHashPointer(key);
        } else {
            attestationId = resolver.collateralPointer(key);
        }
        return resolver.readAttestation(attestationId);
    }

    /**
     * @notice similar with "_fetchDataFromResolver()" but this is called ONLY
     * for collateral reads
     * @dev may overwrite this method to implement additional custom business logic
     */
    function _onFetchDataFromResolver(bytes32 key, bool hash) internal view virtual returns (bytes memory) {
        return _fetchDataFromResolver(key, hash);
    }

    /**
     * @notice check whether the hash for the provided collateral already exists in the PCCS
     * @param key - the key to locate the collateral attestation
     * @param hash - the hash of the collateral
     */
    function _checkCollateralDuplicate(bytes32 key, bytes32 hash) internal view {
        // if a matching hash is found, that means the caller is attempting to re-upsert duplicate collateral
        bytes memory existingHashData = _fetchDataFromResolver(key, true);
        if (existingHashData.length > 0) {
            bytes32 existingHash = abi.decode(existingHashData, (bytes32));
            if (existingHash == hash) {
                revert Duplicate_Collateral();
            }
        }
    }

    /// @dev https://github.com/Vectorized/solady/blob/4964e3e2da1bc86b0394f63a90821f51d60a260b/src/utils/JSONParserLib.sol#L339-L364
    /// @dev Parses an unsigned integer from a string (in hexadecimal, i.e. base 16).
    /// Reverts if `s` is not a valid uint256 hex string matching the RegEx
    /// `^(0[xX])?[0-9a-fA-F]+$`, or if the parsed number is too big for a uint256.
    function _parseUintFromHex(string memory s) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let n := mload(s)
            // Skip two if starts with '0x' or '0X'.
            let i := shl(1, and(eq(0x3078, or(shr(240, mload(add(s, 0x20))), 0x20)), gt(n, 1)))
            for {} 1 {} {
                i := add(i, 1)
                let c :=
                    byte(
                        and(0x1f, shr(and(mload(add(s, i)), 0xff), 0x3e4088843e41bac000000000000)),
                        0x3010a071000000b0104040208000c05090d060e0f
                    )
                n := mul(n, iszero(or(iszero(c), shr(252, result))))
                result := add(shl(4, result), sub(c, 1))
                if iszero(lt(i, n)) { break }
            }
            if iszero(n) {
                mstore(0x00, 0x10182796) // `ParsingFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }
}

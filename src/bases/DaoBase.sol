// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IDaoAttestationResolver.sol";

abstract contract DaoBase {
    IDaoAttestationResolver public resolver;

    constructor(address _resolver) {
        resolver = IDaoAttestationResolver(_resolver);
    }

    /**
     * @dev implement getter logic to retrieve attested data
     * @param key - mapped to a collateral as defined by individual data access objects (DAOs)
     */
    function getAttestedData(bytes32 key) public view virtual returns (bytes memory attestationData) {
        bytes32 attestationId = resolver.collateralPointer(key);
        attestationData = resolver.readAttestation(attestationId);
    }

    /**
     * @dev must store the hash of a collateral (e.g. X509 Cert, TCBInfo JSON etc) in the attestation registry
     * as a separated attestation from the collateral data itself
     */
    function getCollateralHash(bytes32 key) public view virtual returns (bytes32 collateralHash) {
        bytes32 attestationId = resolver.collateralHashPointer(key);
        collateralHash = abi.decode(resolver.readAttestation(attestationId), (bytes32));
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

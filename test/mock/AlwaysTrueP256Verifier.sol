// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract AlwaysTrueP256Verifier {
    fallback() external {
        assembly {
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }
}

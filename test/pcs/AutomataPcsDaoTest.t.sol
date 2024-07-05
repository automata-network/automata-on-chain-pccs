// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataPckDao} from "../../src/automata_pccs/AutomataPckDao.sol";

contract AutomataPcsDaoTest is PCSSetupBase {
    function testPcsGetCertsAndCrls() public {
        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa, bytes memory platformCrl) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));
        assertEq(keccak256(platformCrl), keccak256(pckCrlDer));
    }
}

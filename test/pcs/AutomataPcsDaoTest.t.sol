// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {AutomataDaoBase} from "../../src/automata_pccs/shared/AutomataDaoBase.sol";

contract AutomataPcsDaoTest is PCSSetupBase {
    function testPcsGetCertsAndRootCrl() public readAsAuthorizedCaller {
        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));
    }

    function testUnauthorizedRead() public {
        (, address caller,) = vm.readCallers();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(AutomataDaoBase.Unauthorized_Caller.selector, caller));
        pcs.getCertificateById(CA.ROOT);
    }

    function testCallFromAddressZero() public {
        vm.startPrank(address(0));

        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));

        vm.stopPrank();
    }

    function testPausedCall() public {
        vm.prank(admin);
        pccsStorage.pauseCallerRestriction();

        (bytes memory rootCa, bytes memory rootCrl) = pcs.getCertificateById(CA.ROOT);
        (bytes memory platformCa,) = pcs.getCertificateById(CA.PLATFORM);

        assertEq(keccak256(rootCa), keccak256(rootDer));
        assertEq(keccak256(rootCrl), keccak256(rootCrlDer));
        assertEq(keccak256(platformCa), keccak256(platformDer));
    }

    function testDuplicateUpserts() public {
        // insert root CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.ROOT, rootDer);

        // insert root CRL
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertRootCACrl(rootCrlDer);

        // insert Signing CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.SIGNING, signingDer);

        // insert Platform CA
        vm.expectRevert(abi.encodeWithSelector(DaoBase.Duplicate_Collateral.selector));
        pcs.upsertPcsCertificates(CA.PLATFORM, platformDer);
    }
}

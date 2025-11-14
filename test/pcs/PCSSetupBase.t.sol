// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../TestSetupBase.t.sol";

import {PCSConstants} from "./PCSConstants.t.sol";
import {CA} from "../../src/Common.sol";

abstract contract PCSSetupBase is TestSetupBase, PCSConstants {
    function setUp() public virtual override {
        super.setUp();

        // insert root CA
        pcs.upsertPcsCertificates(CA.ROOT, rootDer);

        // insert root CRL
        pcs.upsertRootCACrl(rootCrlDer);

        // insert Signing CA
        pcs.upsertPcsCertificates(CA.SIGNING, signingDer);

        // insert Platform CA
        pcs.upsertPcsCertificates(CA.PLATFORM, platformDer);
    }
}

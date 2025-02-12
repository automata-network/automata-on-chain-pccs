// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";

import {TCBConstants} from "./TCBConstants.t.sol";

contract AutomataFmspcTcbDaoTest is PCSSetupBase, TCBConstants {
    function setUp() public override {
        super.setUp();
    }

    function testAttestFmspcTcbSgxV2() public {
        uint8 tcbType = 0;
        string memory fmspcStr = "00606a000000";
        bytes6 fmspcBytes = hex"00606a000000";
        uint32 version = 2;

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: string(sgx_v2_tcbStr), signature: sgx_v2_signature});

        bytes32 attestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);
        assertEq(pccsStorage.collateralPointer(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)), attestationId);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetched = fmspcTcbDao.getTcbInfo(tcbType, fmspcStr, version);
        assertEq(fetched.signature, tcbInfoObj.signature);
        assertEq(
            fmspcTcbDao.getCollateralHash(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)),
            sha256(bytes(tcbInfoObj.tcbInfoStr))
        );
        vm.stopPrank();
    }

    function testAttestFmspcTcbSgxV3() public {
        // July 4th, 2024, 2:22:34 AM UTC
        vm.warp(1720059754);

        uint8 tcbType = 0;
        string memory fmspcStr = "10A06D070000";
        bytes6 fmspcBytes = hex"10A06D070000";
        uint32 version = 3;

        TcbInfoJsonObj memory tcbInfoObj =
            TcbInfoJsonObj({tcbInfoStr: string(sgx_v3_tcbStr), signature: sgx_v3_signature});

        bytes32 attestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);
        assertEq(pccsStorage.collateralPointer(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)), attestationId);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetched = fmspcTcbDao.getTcbInfo(tcbType, fmspcStr, version);
        assertEq(fetched.signature, tcbInfoObj.signature);
        assertEq(
            fmspcTcbDao.getCollateralHash(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)),
            sha256(bytes(tcbInfoObj.tcbInfoStr))
        );
        vm.stopPrank();
    }

    function testAttestFmspcTcbTdxV3() public {
        vm.warp(1715843418);

        uint8 tcbType = 1;
        string memory fmspcStr = "90c06f000000";
        bytes6 fmspcBytes = hex"90c06f000000";
        uint32 version = 3;

        TcbInfoJsonObj memory tcbInfoObj = TcbInfoJsonObj({tcbInfoStr: string(tdx_tcbStr), signature: tdx_signature});

        bytes32 attestationId = fmspcTcbDao.upsertFmspcTcb(tcbInfoObj);
        assertEq(pccsStorage.collateralPointer(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)), attestationId);

        vm.startPrank(admin);
        TcbInfoJsonObj memory fetched = fmspcTcbDao.getTcbInfo(tcbType, fmspcStr, version);
        assertEq(fetched.signature, tcbInfoObj.signature);
        assertEq(
            fmspcTcbDao.getCollateralHash(fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version)),
            sha256(bytes(tcbInfoObj.tcbInfoStr))
        );
        vm.stopPrank();
    }

    // attest two tcb infos with identical content
    // then compare collateral and content hashes
    function testAttestAndCompareTcbTdxV3() public {
        vm.warp(1739358000);
        
        string memory str0 = "{\"id\":\"TDX\",\"version\":3,\"issueDate\":\"2025-02-12T10:38:59Z\",\"nextUpdate\":\"2025-03-14T10:38:59Z\",\"fmspc\":\"90c06f000000\",\"pceId\":\"0000\",\"tcbType\":0,\"tcbEvaluationDataNumber\":17,\"tdxModule\":{\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\"},\"tdxModuleIdentities\":[{\"id\":\"TDX_03\",\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\",\"tcbLevels\":[{\"tcb\":{\"isvsvn\":3},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"}]},{\"id\":\"TDX_01\",\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\",\"tcbLevels\":[{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2023-08-09T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}],\"tcbLevels\":[{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":2,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":2,\"category\":\"BIOS\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":1,\"category\":\"BIOS\"},{\"svn\":0},{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"SEAMLDR ACM\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13,\"tdxtcbcomponents\":[{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":0,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TDX Late Microcode Update\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}]},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":2,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":2,\"category\":\"BIOS\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":1,\"category\":\"BIOS\"},{\"svn\":0},{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"SEAMLDR ACM\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":5,\"tdxtcbcomponents\":[{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":0,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TDX Late Microcode Update\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}]},\"tcbDate\":\"2018-01-04T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00106\",\"INTEL-SA-00115\",\"INTEL-SA-00135\",\"INTEL-SA-00203\",\"INTEL-SA-00220\",\"INTEL-SA-00233\",\"INTEL-SA-00270\",\"INTEL-SA-00293\",\"INTEL-SA-00320\",\"INTEL-SA-00329\",\"INTEL-SA-00381\",\"INTEL-SA-00389\",\"INTEL-SA-00477\",\"INTEL-SA-00837\"]}]}";
        bytes memory sig0 = hex"80ee91b992045c78855d915513c6ac47b7bfdb4301210cf328f9250cd4885481d4986cc4d43c585acb2ce3f588715912c7de605d57dcfa0a4210dc8d008f3d60";
        string memory str1 = "{\"id\":\"TDX\",\"version\":3,\"issueDate\":\"2025-02-12T11:39:33Z\",\"nextUpdate\":\"2025-03-14T11:39:33Z\",\"fmspc\":\"90c06f000000\",\"pceId\":\"0000\",\"tcbType\":0,\"tcbEvaluationDataNumber\":17,\"tdxModule\":{\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\"},\"tdxModuleIdentities\":[{\"id\":\"TDX_03\",\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\",\"tcbLevels\":[{\"tcb\":{\"isvsvn\":3},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"}]},{\"id\":\"TDX_01\",\"mrsigner\":\"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\",\"attributes\":\"0000000000000000\",\"attributesMask\":\"FFFFFFFFFFFFFFFF\",\"tcbLevels\":[{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2023-08-09T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}],\"tcbLevels\":[{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":2,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":2,\"category\":\"BIOS\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":1,\"category\":\"BIOS\"},{\"svn\":0},{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"SEAMLDR ACM\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":13,\"tdxtcbcomponents\":[{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":0,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TDX Late Microcode Update\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}]},\"tcbDate\":\"2024-03-13T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"sgxtcbcomponents\":[{\"svn\":2,\"category\":\"BIOS\",\"type\":\"Early Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"SGX Late Microcode Update\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TXT SINIT\"},{\"svn\":2,\"category\":\"BIOS\"},{\"svn\":3,\"category\":\"BIOS\"},{\"svn\":1,\"category\":\"BIOS\"},{\"svn\":0},{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"SEAMLDR ACM\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}],\"pcesvn\":5,\"tdxtcbcomponents\":[{\"svn\":5,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":0,\"category\":\"OS/VMM\",\"type\":\"TDX Module\"},{\"svn\":2,\"category\":\"OS/VMM\",\"type\":\"TDX Late Microcode Update\"},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0},{\"svn\":0}]},\"tcbDate\":\"2018-01-04T00:00:00Z\",\"tcbStatus\":\"OutOfDate\",\"advisoryIDs\":[\"INTEL-SA-00106\",\"INTEL-SA-00115\",\"INTEL-SA-00135\",\"INTEL-SA-00203\",\"INTEL-SA-00220\",\"INTEL-SA-00233\",\"INTEL-SA-00270\",\"INTEL-SA-00293\",\"INTEL-SA-00320\",\"INTEL-SA-00329\",\"INTEL-SA-00381\",\"INTEL-SA-00389\",\"INTEL-SA-00477\",\"INTEL-SA-00837\"]}]}";
        bytes memory sig1 = hex"62d866fbddb83317e0e1ba00ebed622253abf10980c38d70220ad4de529a5dec08b2724e49968ba34f4594cdd1e6d2ccd5300a9dc93c14de53663d4f6bc3526d";

        uint8 tcbType = 1;
        bytes6 fmspcBytes = hex"90c06f000000";
        uint32 version = 3;

        bytes32 key = fmspcTcbDao.FMSPC_TCB_KEY(tcbType, fmspcBytes, version);

        TcbInfoJsonObj memory tcbInfoObj0 = TcbInfoJsonObj({tcbInfoStr: str0, signature: sig0});
        TcbInfoJsonObj memory tcbInfoObj1 = TcbInfoJsonObj({tcbInfoStr: str1, signature: sig1});

        fmspcTcbDao.upsertFmspcTcb(tcbInfoObj0);
        bytes32 collateralHash0 = fmspcTcbDao.getCollateralHash(key);
        assertEq(collateralHash0, sha256(bytes(str0)));
        bytes32 contentHash0 = fmspcTcbDao.getTcbInfoContentHash(key);

        vm.warp(1739360700);
        fmspcTcbDao.upsertFmspcTcb(tcbInfoObj1);
        bytes32 collateralHash1 = fmspcTcbDao.getCollateralHash(key);
        assertEq(collateralHash1, sha256(bytes(str1)));
        bytes32 contentHash1 = fmspcTcbDao.getTcbInfoContentHash(key);

        assertFalse(collateralHash0 == collateralHash1);
        assertEq(contentHash0, contentHash1);
    }

    function testTcbIssuerChain() public readAsAuthorizedCaller {
        (bytes memory fetchedSigning, bytes memory fetchedRoot) = fmspcTcbDao.getTcbIssuerChain();
        assertEq(keccak256(signingDer), keccak256(fetchedSigning));
        assertEq(keccak256(rootDer), keccak256(fetchedRoot));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pcs/PCSSetupBase.t.sol";
import {TCBConstants} from "./TCBConstants.t.sol";
import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {AutomataDaoStorageV2} from "../../src/automata_pccs/shared/AutomataDaoStorageV2.sol";
import {AutomataFmspcTcbDaoVersionedV2} from
    "../../src/automata_pccs/versioned/AutomataFmspcTcbDaoVersionedV2.sol";
import {TcbInfoBasic, TcbInfoJsonObj} from "../../src/helpers/FmspcTcbHelper.sol";
import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";

contract AutomataFmspcTcbDaoV2Test is PCSSetupBase, TCBConstants {
    using JSONParserLib for JSONParserLib.Item;

    AutomataDaoStorageV2 storageV2;
    AutomataFmspcTcbDaoVersionedV2 fmspcTcbDaoV2;
    FmspcTcbHelperV2 fmspcTcbLibV2;
    address attester = address(0x1234);

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        storageV2 = new AutomataDaoStorageV2(admin, address(pccsStorage));
        fmspcTcbLibV2 = new FmspcTcbHelperV2();
        fmspcTcbDaoV2 = new AutomataFmspcTcbDaoVersionedV2(
            address(storageV2),
            P256_VERIFIER,
            address(pcs),
            address(fmspcTcbLib),
            address(fmspcTcbLibV2),
            address(x509Lib),
            address(x509CrlLib),
            admin,
            16
        );

        pccsStorage.grantDao(address(storageV2));
        storageV2.grantDao(admin);
        storageV2.grantDao(address(fmspcTcbDaoV2));
        storageV2.setCallerAuthorization(admin, true);
        fmspcTcbDaoV2.grantRoles(attester, fmspcTcbDaoV2.ATTESTER_ROLE());
        vm.stopPrank();
    }

    function testLegacyAttestFallsBackToStorageV1() public {
        bytes32 key = keccak256("legacy-sync-key");
        bytes memory data = abi.encodePacked("legacy-sync-data");
        bytes32 dataHash = sha256(data);

        vm.prank(admin);
        (bytes32 attestationId, bytes32 hashAttestationId) = storageV2.attest(key, data, dataHash);

        vm.startPrank(admin);
        assertEq(storageV2.refForAttestation(attestationId), bytes32(0));
        assertEq(storageV2.readAttestation(attestationId), data);
        assertEq(storageV2.readAttestation(hashAttestationId), abi.encodePacked(dataHash));
        vm.stopPrank();
    }

    function testAsyncUpsertSgxV2() public {
        bytes32 refId = keccak256("sgx-v2-async");
        uint8 tcbType = 0;
        bytes6 fmspcBytes = hex"00606a000000";
        uint32 version = 2;
        string[] memory levelObjects = _extractObjectArray(string(sgx_v2_tcbStr), "tcbLevels");

        vm.startPrank(attester);
        fmspcTcbDaoV2.startAsyncUpsert(refId, sgx_v2_signature);
        fmspcTcbDaoV2.uploadChunkData(refId, sgx_v2_tcbStr);
        uint256 start;
        while (start < levelObjects.length) {
            string[] memory batch = _sliceStrings(levelObjects, start, 3);
            (uint256 parsed,,) = fmspcTcbDaoV2.uploadParsedTcbLevelsBatch(refId, start, batch);
            start += parsed;
        }

        bytes32 key = fmspcTcbDaoV2.FMSPC_TCB_KEY(tcbType, fmspcBytes, version);
        bytes32 attestationId = storageV2.collateralPointer(key);
        fmspcTcbDaoV2.finalizeAsyncUpsert(attestationId, refId);
        vm.stopPrank();

        vm.startPrank(admin);
        bytes memory payload = fmspcTcbDaoV2.getAttestedData(key);
        assertGt(payload.length, 4);
        assertEq(storageV2.refForAttestation(attestationId), bytes32(0));

        (TcbInfoBasic memory basic, bytes memory encodedLevels, TcbInfoJsonObj memory attestedObj) =
            abi.decode(payload, (TcbInfoBasic, bytes, TcbInfoJsonObj));
        assertEq(uint8(basic.id), tcbType);
        assertEq(basic.fmspc, fmspcBytes);
        assertEq(basic.version, version);
        assertGt(encodedLevels.length, 0);
        assertEq(bytes(attestedObj.tcbInfoStr), sgx_v2_tcbStr);
        assertEq(attestedObj.signature, sgx_v2_signature);

        TcbInfoJsonObj memory fetched = fmspcTcbDaoV2.getTcbInfo(tcbType, "00606a000000", version);
        assertEq(bytes(fetched.tcbInfoStr), sgx_v2_tcbStr);
        assertEq(fetched.signature, sgx_v2_signature);
        assertEq(fmspcTcbDaoV2.getCollateralHash(key), sha256(sgx_v2_tcbStr));
        vm.stopPrank();
    }

    function _extractObjectArray(string memory json, string memory fieldName)
        internal
        pure
        returns (string[] memory objects)
    {
        JSONParserLib.Item memory root = JSONParserLib.parse(json);
        JSONParserLib.Item[] memory fields = root.children();
        for (uint256 i = 0; i < fields.length; i++) {
            if (keccak256(bytes(JSONParserLib.decodeString(fields[i].key()))) == keccak256(bytes(fieldName))) {
                JSONParserLib.Item[] memory items = fields[i].children();
                objects = new string[](items.length);
                for (uint256 j = 0; j < items.length; j++) {
                    objects[j] = items[j].value();
                }
                return objects;
            }
        }
        return new string[](0);
    }

    function _sliceStrings(string[] memory items, uint256 start, uint256 maxLength)
        internal
        pure
        returns (string[] memory batch)
    {
        uint256 length = maxLength;
        if (start + length > items.length) {
            length = items.length - start;
        }
        batch = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            batch[i] = items[start + i];
        }
    }
}

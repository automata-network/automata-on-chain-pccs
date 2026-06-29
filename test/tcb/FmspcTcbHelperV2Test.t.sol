// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {FmspcTcbHelperV2} from "../../src/helpers/FmspcTcbHelperV2.sol";

contract FmspcTcbHelperV2Test is Test {
    FmspcTcbHelperV2 helper;

    function setUp() public {
        helper = new FmspcTcbHelperV2();
    }

    function testBuildAsyncTcbLevelsBatchV2Schema() public {
        bytes16 svns = 0x01010101010101010101010101010101;
        bytes20 tcbDate = bytes20("2024-01-01T00:00:00Z");
        bytes memory payload = abi.encodePacked(
            uint8(0),
            uint32(1),
            uint32(398),
            bytes4(hex"01020300"),
            bytes3(0),
            uint8(0),
            svns,
            uint32(13),
            tcbDate,
            uint8(0),
            uint32(0)
        );

        FmspcTcbHelperV2.AsyncBuiltBatch memory batch = helper.buildAsyncTcbLevelsBatch(2, payload, 1, false);
        assertEq(batch.rawStart, 1);
        assertEq(batch.packedStream.length, 68);
        assertEq(
            string(batch.rawJson),
            string(
                abi.encodePacked(
                    '{"tcb":{"sgxtcbcomp01svn":1,"sgxtcbcomp02svn":1,"sgxtcbcomp03svn":1,',
                    '"sgxtcbcomp04svn":1,"sgxtcbcomp05svn":1,"sgxtcbcomp06svn":1,',
                    '"sgxtcbcomp07svn":1,"sgxtcbcomp08svn":1,"sgxtcbcomp09svn":1,',
                    '"sgxtcbcomp10svn":1,"sgxtcbcomp11svn":1,"sgxtcbcomp12svn":1,',
                    '"sgxtcbcomp13svn":1,"sgxtcbcomp14svn":1,"sgxtcbcomp15svn":1,',
                    '"sgxtcbcomp16svn":1,"pcesvn":13},"tcbDate":"2024-01-01T00:00:00Z",',
                    '"tcbStatus":"UpToDate"}'
                )
            )
        );
    }
}

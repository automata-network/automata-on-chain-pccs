// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

abstract contract IdentityConstants {
    string internal identityStr =
        "{\"id\":\"QE\",\"version\":2,\"issueDate\":\"2024-06-19T07:22:26Z\",\"nextUpdate\":\"2024-07-19T07:22:26Z\",\"tcbEvaluationDataNumber\":16,\"miscselect\":\"00000000\",\"miscselectMask\":\"FFFFFFFF\",\"attributes\":\"11000000000000000000000000000000\",\"attributesMask\":\"FBFFFFFFFFFFFFFF0000000000000000\",\"mrsigner\":\"8C4F5775D796503E96137F77C68A829A0056AC8DED70140B081B094490C57BFF\",\"isvprodid\":1,\"tcbLevels\":[{\"tcb\":{\"isvsvn\":8},\"tcbDate\":\"2023-08-09T00:00:00Z\",\"tcbStatus\":\"UpToDate\"},{\"tcb\":{\"isvsvn\":6},\"tcbDate\":\"2021-11-10T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":5},\"tcbDate\":\"2020-11-11T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":4},\"tcbDate\":\"2019-11-13T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":2},\"tcbDate\":\"2019-05-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"},{\"tcb\":{\"isvsvn\":1},\"tcbDate\":\"2018-08-15T00:00:00Z\",\"tcbStatus\":\"OutOfDate\"}]}";
    bytes internal signature =
        hex"11c3d0f27c16b890e5ab761cdddee355f1bb1b54d25a51cbdfec16997dafe4de4403de2548f0cd2d4a1e02b1a933893417ae87bc77259d0daa0f4f56ce40c032";
}

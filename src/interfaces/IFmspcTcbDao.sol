// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct TcbInfoJsonObj {
    string tcbInfoStr;
    bytes signature;
}

interface IFmspcTcbDao {
    function getTcbInfo(uint256 tcbType, string calldata fmspc, uint256 version)
        external
        view
        returns (TcbInfoJsonObj memory tcbObj);

    function getTcbIssuerChain() external view returns (bytes memory signingCert, bytes memory rootCert);

    function upsertFmspcTcb(TcbInfoJsonObj calldata tcbInfoObj) external returns (bytes32 attestationId);
}

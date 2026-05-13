// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DateTimeUtils} from "../utils/DateTimeUtils.sol";
import {BytesUtils} from "../utils/BytesUtils.sol";
import {
    TCBLevelsObj,
    TDXModuleIdentity,
    TDXModuleTCBLevelsObj,
    TCBStatus
} from "./FmspcTcbHelper.sol";

uint256 constant TCB_CPUSVN_SIZE_V2 = 16;

contract FmspcTcbHelperV2 {
    using JSONParserLib for JSONParserLib.Item;
    using LibString for string;
    using BytesUtils for bytes;

    error TCBInfo_Invalid();

    function countTcbLevels(string calldata tcbLevelsString) external pure returns (uint256 total) {
        JSONParserLib.Item memory root = JSONParserLib.parse(tcbLevelsString);
        total = root.children().length;
    }

    function countTdxModuleIdentities(string calldata tdxModuleIdentitiesString) external pure returns (uint256 total) {
        JSONParserLib.Item memory root = JSONParserLib.parse(tdxModuleIdentitiesString);
        total = root.children().length;
    }

    function parseTcbLevelObjects(uint256 version, string[] calldata rawLevelObjects)
        external
        pure
        returns (bytes memory packedTcbLevels, uint256 parsed)
    {
        uint256 n = rawLevelObjects.length;
        for (uint256 i = 0; i < n; i++) {
            JSONParserLib.Item memory item = JSONParserLib.parse(rawLevelObjects[i]);
            TCBLevelsObj memory level = _parseTcbLevelObject(version, item);
            bytes memory encoded = _tcbLevelsObjToBytes(level);
            packedTcbLevels = bytes.concat(packedTcbLevels, abi.encodePacked(uint32(encoded.length), encoded));
            parsed++;
        }
    }

    function parseTdxModuleIdentityObjects(string[] calldata rawIdentityObjects)
        external
        pure
        returns (bytes memory packedTdxModuleIdentities, uint256 parsed)
    {
        uint256 n = rawIdentityObjects.length;
        for (uint256 i = 0; i < n; i++) {
            JSONParserLib.Item memory item = JSONParserLib.parse(rawIdentityObjects[i]);
            TDXModuleIdentity memory identity = _parseTdxModuleIdentityObject(item);
            bytes memory encoded = _tdxModuleIdentityToBytes(identity);
            packedTdxModuleIdentities =
                bytes.concat(packedTdxModuleIdentities, abi.encodePacked(uint32(encoded.length), encoded));
            parsed++;
        }
    }

    function _parseTcbLevelObject(uint256 version, JSONParserLib.Item memory tcbLevelItem)
        private
        pure
        returns (TCBLevelsObj memory level)
    {
        JSONParserLib.Item[] memory tcbObj = tcbLevelItem.children();
        for (uint256 j = 0; j < tcbLevelItem.size(); j++) {
            string memory tcbKey = JSONParserLib.decodeString(tcbObj[j].key());
            if (tcbKey.eq("tcb")) {
                string memory tcbStr = tcbObj[j].value();
                JSONParserLib.Item memory tcbParent = JSONParserLib.parse(tcbStr);
                JSONParserLib.Item[] memory tcbComponents = tcbParent.children();
                if (version == 2) {
                    (level.sgxComponentCpuSvns, level.pcesvn) = _parseV2Tcb(tcbComponents);
                } else if (version == 3) {
                    (level.sgxComponentCpuSvns, level.tdxComponentCpuSvns, level.pcesvn) =
                        _parseV3Tcb(tcbComponents);
                } else {
                    revert TCBInfo_Invalid();
                }
            } else if (tcbKey.eq("tcbDate")) {
                level.tcbDateTimestamp =
                    uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(tcbObj[j].value())));
            } else if (tcbKey.eq("tcbStatus")) {
                level.status = _getTcbStatus(JSONParserLib.decodeString(tcbObj[j].value()));
            } else if (tcbKey.eq("advisoryIDs")) {
                JSONParserLib.Item[] memory advisoryArr = tcbObj[j].children();
                uint256 n = tcbObj[j].size();
                level.advisoryIDs = new string[](n);
                for (uint256 k = 0; k < n; k++) {
                    level.advisoryIDs[k] = JSONParserLib.decodeString(advisoryArr[k].value());
                }
            }
        }
    }

    function _parseTdxModuleIdentityObject(JSONParserLib.Item memory identityItem)
        private
        pure
        returns (TDXModuleIdentity memory identity)
    {
        JSONParserLib.Item[] memory currIdentity = identityItem.children();
        for (uint256 j = 0; j < identityItem.size(); j++) {
            string memory key = JSONParserLib.decodeString(currIdentity[j].key());
            if (key.eq("id")) {
                identity.id = JSONParserLib.decodeString(currIdentity[j].value());
            } else if (key.eq("mrsigner")) {
                identity.mrsigner = _getMrSignerHex(JSONParserLib.decodeString(currIdentity[j].value()));
            } else if (key.eq("attributes")) {
                identity.attributes =
                    bytes8(uint64(JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(currIdentity[j].value()))));
            } else if (key.eq("attributesMask")) {
                identity.attributesMask =
                    bytes8(uint64(JSONParserLib.parseUintFromHex(JSONParserLib.decodeString(currIdentity[j].value()))));
            } else if (key.eq("tcbLevels")) {
                identity.tcbLevels = _parseTdxModuleTcbLevels(currIdentity[j]);
            }
        }
    }

    function _parseTdxModuleTcbLevels(JSONParserLib.Item memory tcbLevelsItem)
        private
        pure
        returns (TDXModuleTCBLevelsObj[] memory levels)
    {
        JSONParserLib.Item[] memory tcbLevelsArr = tcbLevelsItem.children();
        uint256 count = tcbLevelsArr.length;
        levels = new TDXModuleTCBLevelsObj[](count);
        for (uint256 i = 0; i < count; i++) {
            levels[i] = _parseTdxModuleTcbLevel(tcbLevelsArr[i]);
        }
    }

    function _parseTdxModuleTcbLevel(JSONParserLib.Item memory tcbLevelItem)
        private
        pure
        returns (TDXModuleTCBLevelsObj memory level)
    {
        JSONParserLib.Item[] memory fields = tcbLevelItem.children();
        for (uint256 i = 0; i < fields.length; i++) {
            string memory key = JSONParserLib.decodeString(fields[i].key());
            if (key.eq("tcb")) {
                JSONParserLib.Item[] memory isvsvnObj = fields[i].children();
                if (!JSONParserLib.decodeString(isvsvnObj[0].key()).eq("isvsvn")) revert TCBInfo_Invalid();
                level.isvsvn = uint8(JSONParserLib.parseUint(isvsvnObj[0].value()));
            } else if (key.eq("tcbDate")) {
                level.tcbDateTimestamp =
                    uint64(DateTimeUtils.fromISOToTimestamp(JSONParserLib.decodeString(fields[i].value())));
            } else if (key.eq("tcbStatus")) {
                level.status = _getTcbStatus(JSONParserLib.decodeString(fields[i].value()));
            }
        }
    }

    function _tcbLevelsObjToBytes(TCBLevelsObj memory obj) private pure returns (bytes memory serialized) {
        uint256 firstSlot = uint256(obj.pcesvn) << (2 * 64) | uint256(obj.tcbDateTimestamp) << 64 | uint8(obj.status);
        uint256 secondSlot;
        uint256 n = obj.sgxComponentCpuSvns.length;
        for (uint256 i = 0; i < n;) {
            uint256 v1Shift = 8 * ((2 * n) - i - 1);
            secondSlot |= uint256(obj.sgxComponentCpuSvns[i]) << v1Shift;
            unchecked {
                i++;
            }
        }
        if (obj.tdxComponentCpuSvns.length > 0) {
            for (uint256 i = 0; i < n;) {
                uint256 v2Shift = 8 * (n - i - 1);
                secondSlot |= uint256(obj.tdxComponentCpuSvns[i]) << v2Shift;
                unchecked {
                    i++;
                }
            }
        }

        bytes memory stringSlot;
        if (obj.advisoryIDs.length > 0) {
            string memory concat = obj.advisoryIDs[0];
            for (uint256 j = 1; j < obj.advisoryIDs.length; j++) {
                concat = string.concat(concat, "\n", obj.advisoryIDs[j]);
            }
            stringSlot = bytes(concat);
        }

        serialized = abi.encodePacked(firstSlot, secondSlot, stringSlot);
    }

    function _tdxModuleIdentityToBytes(TDXModuleIdentity memory tdxModuleIdentity)
        private
        pure
        returns (bytes memory packedTdxModuleIdentity)
    {
        bytes32 slot1 = LibString.packOne(tdxModuleIdentity.id);
        bytes32 slot2 = bytes32(tdxModuleIdentity.mrsigner);
        bytes32 slot3 = bytes32(abi.encodePacked(tdxModuleIdentity.mrsigner.substring(32, 16), bytes16(0)));
        bytes32 slot4 = bytes32(tdxModuleIdentity.attributes) | bytes32(tdxModuleIdentity.attributesMask) >> 128;

        uint256 n = tdxModuleIdentity.tcbLevels.length;
        uint256[] memory tdxTcbSlots = new uint256[](n);
        for (uint256 i = 0; i < n;) {
            tdxTcbSlots[i] = _tdxModuleTcbLevelsObjToSlot(tdxModuleIdentity.tcbLevels[i]);
            unchecked {
                i++;
            }
        }

        packedTdxModuleIdentity = abi.encodePacked(slot1, slot2, slot3, slot4, abi.encodePacked(tdxTcbSlots));
    }

    function _tdxModuleTcbLevelsObjToSlot(TDXModuleTCBLevelsObj memory tdxModuleTcbLevelsObj)
        private
        pure
        returns (uint256 tdxTcbPacked)
    {
        tdxTcbPacked = uint256(tdxModuleTcbLevelsObj.isvsvn) << (2 * 64)
            | uint256(tdxModuleTcbLevelsObj.tcbDateTimestamp) << 64 | uint8(tdxModuleTcbLevelsObj.status);
    }

    function _parseV2Tcb(JSONParserLib.Item[] memory tcbComponents)
        private
        pure
        returns (uint8[] memory sgxComponentCpuSvns, uint16 pcesvn)
    {
        sgxComponentCpuSvns = new uint8[](TCB_CPUSVN_SIZE_V2);
        uint256 cpusvnCounter;
        for (uint256 i = 0; i < tcbComponents.length; i++) {
            string memory key = JSONParserLib.decodeString(tcbComponents[i].key());
            uint256 value = JSONParserLib.parseUint(tcbComponents[i].value());
            if (key.eq("pcesvn")) {
                pcesvn = uint16(value);
            } else {
                sgxComponentCpuSvns[cpusvnCounter++] = uint8(value);
            }
        }
        if (cpusvnCounter != TCB_CPUSVN_SIZE_V2) revert TCBInfo_Invalid();
    }

    function _parseV3Tcb(JSONParserLib.Item[] memory tcbComponents)
        private
        pure
        returns (uint8[] memory sgxComponentCpuSvns, uint8[] memory tdxComponentCpuSvns, uint16 pcesvn)
    {
        sgxComponentCpuSvns = new uint8[](TCB_CPUSVN_SIZE_V2);
        tdxComponentCpuSvns = new uint8[](TCB_CPUSVN_SIZE_V2);
        for (uint256 i = 0; i < tcbComponents.length; i++) {
            string memory key = JSONParserLib.decodeString(tcbComponents[i].key());
            if (key.eq("pcesvn")) {
                pcesvn = uint16(JSONParserLib.parseUint(tcbComponents[i].value()));
            } else {
                string memory componentKey = key;
                JSONParserLib.Item[] memory componentArr = tcbComponents[i].children();
                uint256 cpusvnCounter;
                for (uint256 j = 0; j < tcbComponents[i].size(); j++) {
                    JSONParserLib.Item[] memory component = componentArr[j].children();
                    for (uint256 k = 0; k < componentArr[j].size(); k++) {
                        key = JSONParserLib.decodeString(component[k].key());
                        if (key.eq("svn")) {
                            if (componentKey.eq("tdxtcbcomponents")) {
                                tdxComponentCpuSvns[cpusvnCounter++] = uint8(JSONParserLib.parseUint(component[k].value()));
                            } else {
                                sgxComponentCpuSvns[cpusvnCounter++] = uint8(JSONParserLib.parseUint(component[k].value()));
                            }
                        }
                    }
                }
                if (cpusvnCounter != TCB_CPUSVN_SIZE_V2) revert TCBInfo_Invalid();
            }
        }
    }

    function _getTcbStatus(string memory statusStr) private pure returns (TCBStatus status) {
        if (statusStr.eq("UpToDate")) {
            status = TCBStatus.OK;
        } else if (statusStr.eq("OutOfDate")) {
            status = TCBStatus.TCB_OUT_OF_DATE;
        } else if (statusStr.eq("OutOfDateConfigurationNeeded")) {
            status = TCBStatus.TCB_OUT_OF_DATE_CONFIGURATION_NEEDED;
        } else if (statusStr.eq("ConfigurationNeeded")) {
            status = TCBStatus.TCB_CONFIGURATION_NEEDED;
        } else if (statusStr.eq("ConfigurationAndSWHardeningNeeded")) {
            status = TCBStatus.TCB_CONFIGURATION_AND_SW_HARDENING_NEEDED;
        } else if (statusStr.eq("SWHardeningNeeded")) {
            status = TCBStatus.TCB_SW_HARDENING_NEEDED;
        } else if (statusStr.eq("Revoked")) {
            status = TCBStatus.TCB_REVOKED;
        } else {
            status = TCBStatus.TCB_UNRECOGNIZED;
        }
    }

    function _getMrSignerHex(string memory mrSignerStr) private pure returns (bytes memory mrSignerBytes) {
        string memory mrSignerUpper16BytesStr = mrSignerStr.slice(0, 16);
        string memory mrSignerLower32BytesStr = mrSignerStr.slice(16, 48);
        uint256 mrSignerUpperBytes = JSONParserLib.parseUintFromHex(mrSignerUpper16BytesStr);
        uint256 mrSignerLowerBytes = JSONParserLib.parseUintFromHex(mrSignerLower32BytesStr);
        mrSignerBytes = abi.encodePacked(uint128(mrSignerUpperBytes), mrSignerLowerBytes);
    }
}

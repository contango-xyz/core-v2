// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import { Vm } from "forge-std/Vm.sol";
import "src/libraries/DataTypes.sol";

bytes constant POSITION_UPSERTED = "PositionUpserted(bytes32,address,address,uint8,int256,int256,uint256,uint256,uint8)";
bytes constant STRATEGY_EXECUTED = "StragegyExecuted(address,bytes32,bytes32,bytes32,bytes)";

function bytes32ToString(bytes32 _bytes32) pure returns (string memory) {
    uint8 i = 0;
    while (i < 32 && _bytes32[i] != 0) i++;
    bytes memory bytesArray = new bytes(i);
    for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
        bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
}

function first(Vm.Log[] memory logs, bytes memory _event) pure returns (Vm.Log memory) {
    for (uint256 i = 0; i < logs.length; i++) {
        if (logs[i].topics[0] == keccak256(_event)) return logs[i];
    }
    revert(string.concat(string(_event), " not found"));
}

function all(Vm.Log[] memory logs, bytes memory _event) pure returns (Vm.Log[] memory result) {
    uint256 count;
    result = new Vm.Log[](logs.length);

    for (uint256 i = 0; i < logs.length; i++) {
        if (logs[i].topics[0] == keccak256(_event)) result[count++] = logs[i];
    }

    assembly {
        mstore(result, count)
    }

    return result;
}

function positionsUpserted(Vm.Log[] memory logs) pure returns (PositionId[] memory positions) {
    positions = new PositionId[](logs.length);
    uint256 j;
    for (uint256 i = 0; i < logs.length; i++) {
        if (logs[i].topics[0] == keccak256(POSITION_UPSERTED)) positions[j++] = PositionId.wrap(logs[i].topics[1]);
    }
    assembly {
        mstore(positions, j)
    }
}

struct StrategyExecuted {
    address user;
    string action;
    PositionId position1;
    PositionId position2;
    bytes data;
}

function strategyExecuted(Vm.Log[] memory logs) pure returns (StrategyExecuted memory) {
    for (uint256 i = 0; i < logs.length; i++) {
        if (logs[i].topics[0] == keccak256(STRATEGY_EXECUTED)) {
            (PositionId position1, PositionId position2, bytes memory data) = abi.decode(logs[i].data, (PositionId, PositionId, bytes));
            return StrategyExecuted({
                user: asAddress(logs[i].topics[1]),
                action: bytes32ToString(logs[i].topics[2]),
                position1: position1,
                position2: position2,
                data: data
            });
        }
    }
    revert("StrategyExecuted not found");
}

function positionUpserted(Vm.Log[] memory logs) pure returns (PositionId) {
    Vm.Log memory log = first(logs, POSITION_UPSERTED);
    return PositionId.wrap(log.topics[1]);
}

function asAddress(bytes32 b) pure returns (address) {
    return address(uint160(uint256(b)));
}

function fill(uint256 length, address a) pure returns (address[] memory addresses) {
    addresses = new address[](length);
    for (uint256 i = 0; i < length; ++i) {
        addresses[i] = a;
    }
}

function push(address[] calldata a, address b) pure returns (address[] memory addresses) {
    addresses = new address[](a.length + 1);
    for (uint256 i = 0; i < a.length; ++i) {
        addresses[i] = a[i];
    }
    addresses[a.length] = b;
}

function toArray(uint256 n, uint256 n2) pure returns (uint256[] memory arr) {
    arr = new uint256[](2);
    arr[0] = n;
    arr[1] = n2;
}

// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

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

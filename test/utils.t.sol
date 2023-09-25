// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/Test.sol";

function bytes32ToString(bytes32 _bytes32) pure returns (string memory) {
    bytes memory bytesArray = new bytes(32);

    for (uint256 i = 0; i < 32; i++) {
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

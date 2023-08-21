// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

function bytes32ToString(bytes32 _bytes32) pure returns (string memory) {
    bytes memory bytesArray = new bytes(32);

    for (uint256 i = 0; i < 32; i++) {
        bytesArray[i] = _bytes32[i];
    }

    return string(bytesArray);
}

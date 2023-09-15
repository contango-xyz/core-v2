//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

error InvalidUInt8(uint256 n);

function isBitSet(bytes1 flags, uint256 bit) pure returns (bool) {
    if (bit > 7) revert InvalidUInt8(bit);
    bytes1 mask = bytes1(0x01) << bit;
    return (flags & mask) != bytes1(0);
}

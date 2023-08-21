//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

function toArray(uint256 n) pure returns (uint256[] memory arr) {
    arr = new uint[](1);
    arr[0] = n;
}

function toArray(address a) pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
}

function toArray(address a, address b) pure returns (address[] memory arr) {
    arr = new address[](2);
    arr[0] = a;
    arr[1] = b;
}

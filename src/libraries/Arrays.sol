//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

function toArray(uint256 n) pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = n;
}

function toArray(address a) pure returns (address[] memory arr) {
    arr = new address[](1);
    arr[0] = a;
}

function toStringArray(string memory a) pure returns (string[] memory arr) {
    arr = new string[](1);
    arr[0] = a;
}

function toArray(bytes memory a) pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = a;
}

function toArray(address a, address b) pure returns (address[] memory arr) {
    arr = new address[](2);
    arr[0] = a;
    arr[1] = b;
}

function toArray(IERC20 a) pure returns (IERC20[] memory arr) {
    arr = new IERC20[](1);
    arr[0] = a;
}

function toArray(IERC20 a, IERC20 b) pure returns (IERC20[] memory arr) {
    arr = new IERC20[](2);
    arr[0] = a;
    arr[1] = b;
}

function toStringArray(string memory a, string memory b) pure returns (string[] memory arr) {
    arr = new string[](2);
    arr[0] = a;
    arr[1] = b;
}

function toArray(bytes memory a, bytes memory b) pure returns (bytes[] memory arr) {
    arr = new bytes[](2);
    arr[0] = a;
    arr[1] = b;
}

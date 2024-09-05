//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/StdStorage.sol";

// slot complexity:
//  if flat, will be bytes32(uint256(uint));
//  if map, will be keccak256(abi.encode(key, uint(slot)));
//  if deep map, will be keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))));
//  if map struct, will be bytes32(uint256(keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))))) + structFieldDepth);
contract StorageUtils {

    using stdStorage for StdStorage;

    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address internal immutable contractAddress;

    constructor(address _contractAddress) {
        contractAddress = _contractAddress;
    }

    function read(bytes32 key) public view returns (bytes memory) {
        return abi.encode(vm.load(address(contractAddress), bytes32(key)));
    }

    function read_bytes32(bytes32 key) public view returns (bytes32) {
        return abi.decode(read(key), (bytes32));
    }

    function read_address(bytes32 key) public view returns (address) {
        return abi.decode(read(key), (address));
    }

    function read_uint(bytes32 key) public view returns (uint256) {
        return abi.decode(read(key), (uint256));
    }

}

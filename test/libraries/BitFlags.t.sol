//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { isBitSet } from "src/libraries/BitFlags.sol";
import { setBit } from "../Encoder.sol";

contract BitFlagsTest is Test {

    bytes1 flags;

    function test_setBit() public {
        for (uint256 i = 0; i < 8; i++) {
            flags = setBit(flags, i);
            assertTrue(isBitSet(flags, i), "bit should be set");
        }
    }

    function testFail_bitOverflow() public view {
        setBit(flags, 8); // This should fail, as there are only bits 0-7 in a byte
    }

}

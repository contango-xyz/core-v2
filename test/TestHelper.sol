// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/StdAssertions.sol";
import "forge-std/StdCheats.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./TestSetup.t.sol";

contract TestHelper is StdAssertions, StdCheats {

    function assertNoBalances(IERC20 token, address addr, uint256 dust, string memory label) public {
        uint256 balance = address(token) == address(0) ? addr.balance : token.balanceOf(addr);
        assertApproxEqAbsDecimal(balance, 0, dust, token.decimals(), label);
    }

}

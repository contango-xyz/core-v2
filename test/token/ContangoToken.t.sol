//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";

import { ContangoToken } from "src/token/ContangoToken.sol";

contract ContangoTokenTest is BaseTest {

    address constant OWNER = address(0xdeadbeef);

    ContangoToken internal sut;

    function setUp() public {
        sut = new ContangoToken(OWNER);
    }

    function testPermissions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        sut.mint(address(0), 0);
    }

    function testCanOnlyBurnOwnBalance() public {
        address trader = address(0xb0b0);

        vm.startPrank(OWNER);
        sut.mint(OWNER, 1);
        sut.transfer(trader, 1);
        vm.stopPrank();

        vm.startPrank(trader);

        assertEq(sut.balanceOf(trader), 1, "balance before burn");
        sut.burn(1);
        assertEq(sut.balanceOf(trader), 0, "balance after burn");

        vm.expectRevert("ERC20: burn amount exceeds balance");
        sut.burn(1);
    }

    function testCanOnlyMintUpToMaxSupply() public {
        uint256 maxSupply = sut.MAX_SUPPLY();

        vm.expectRevert(ContangoToken.MaxSupplyExceeded.selector);
        vm.prank(OWNER);
        sut.mint(OWNER, maxSupply + 1);
    }

    function testCanReMintAfterBurn() public {
        vm.startPrank(OWNER);

        sut.mint(OWNER, sut.MAX_SUPPLY());
        assertEq(sut.totalSupply(), sut.MAX_SUPPLY(), "total supply after mint");

        sut.burn(1);
        assertEq(sut.totalSupply(), sut.MAX_SUPPLY() - 1, "total supply after burn");

        sut.mint(OWNER, 1);
        assertEq(sut.totalSupply(), sut.MAX_SUPPLY(), "total supply after re-mint");
    }

}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "src/core/PositionNFT.sol";

contract PositionNFTTest is BaseTest {

    address private trader1;
    address private trader2;
    address private minter;

    PositionNFT private sut;

    Symbol symbol1 = Symbol.wrap("ETH/USD");
    Symbol symbol2 = Symbol.wrap("BTC/USD");

    MoneyMarketId mm1 = MM_AAVE;
    MoneyMarketId mm2 = MM_COMPOUND;

    function setUp() public {
        trader1 = address(0xb0b);
        trader2 = address(0xa11ce);
        minter = address(0x7eca);

        sut = new PositionNFT(TIMELOCK);
        vm.startPrank(TIMELOCK_ADDRESS);
        sut.grantRole(MINTER_ROLE, minter);
        vm.stopPrank();
    }

    function testMintIsProtected() public {
        expectAccessControl(trader1, MINTER_ROLE);
        sut.mint(encode(symbol1, mm1, PERP, 0, 0), trader1);
    }

    function testSetContangoContractIsProtected() public {
        expectAccessControl(trader1, DEFAULT_ADMIN_ROLE);
        sut.setContangoContract(address(0), true);
    }

    function testBurnIsProtected() public {
        expectAccessControl(trader1, MINTER_ROLE);
        sut.burn(PositionId.wrap(0));
    }

    function testMint() public {
        uint256 nextCounter = sut.counter();

        vm.startPrank(minter);
        PositionId nft1 = sut.mint(encode(symbol1, mm1, PERP, 0, 0), trader1);
        PositionId nft2 = sut.mint(encode(symbol1, mm1, 1234, 0, 0), trader2);
        PositionId nft3 = sut.mint(encode(symbol2, mm2, PERP, 0, 0), trader1);

        assertEq(nextCounter, 1);
        assertPositionId(nft1, symbol1, mm1, PERP, 1);
        assertPositionId(nft2, symbol1, mm1, 1234, 2);
        assertPositionId(nft3, symbol2, mm2, PERP, 3);
        assertEq(sut.counter(), 4);

        assertEq(sut.balanceOf(trader1), 2);
        assertEq(sut.balanceOf(trader2), 1);
    }

    function assertPositionId(PositionId positionId, Symbol symbol, MoneyMarketId mm, uint32 expiry, uint256 number) private pure {
        (Symbol s, MoneyMarketId m, uint32 e, uint256 n) = positionId.decode();
        assertEq(Symbol.unwrap(s), Symbol.unwrap(symbol), "symbol");
        assertEq(MoneyMarketId.unwrap(m), MoneyMarketId.unwrap(mm), "mm");
        assertEq(n, number, "number");
        assertEq(e, expiry, "expiry");
    }

    function testBurn() public {
        vm.startPrank(minter);
        PositionId nft1 = sut.mint(encode(symbol1, mm1, PERP, 0, 0), trader1);
        sut.mint(encode(symbol1, mm1, PERP, 0, 0), trader2);
        sut.mint(encode(symbol1, mm1, PERP, 0, 0), trader1);

        sut.burn(nft1);

        assertEq(sut.counter(), 4);

        assertEq(sut.balanceOf(trader1), 1);
        assertEq(sut.balanceOf(trader2), 1);
    }

    function testIsApprovedForAll() public {
        assertTrue(sut.isApprovedForAll(trader1, trader1), "caller trader1");

        address contango = makeAddr("contango");
        vm.prank(TIMELOCK_ADDRESS);
        sut.setContangoContract(contango, true);
        assertTrue(sut.isApprovedForAll(trader1, contango), "caller contango");

        address delegate = makeAddr("delegate");
        vm.prank(trader1);
        sut.setApprovalForAll(delegate, true);
        assertTrue(sut.isApprovedForAll(trader1, delegate), "caller delegate");

        assertFalse(sut.isApprovedForAll(trader1, trader2), "caller trader2");
    }

}

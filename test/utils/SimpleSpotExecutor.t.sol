//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../BaseTest.sol";
import "../TestSetup.t.sol";

contract SimpleSpotExecutorTest is SimpleSpotExecutorEvents, SimpleSpotExecutorErrors, BaseTest {

    using SafeERC20 for ERC20;

    ERC20 private tokenA;
    ERC20 private tokenB;
    MockRouter private mockRouter;
    SimpleSpotExecutor private sut;

    function setUp() public {
        tokenA = new ERC20("Token A", "TKN_A");
        tokenB = new ERC20("Token B", "TKN_B");

        mockRouter = new MockRouter();
        sut = new SimpleSpotExecutor();
    }

    function testExecuteSwap() public {
        // given
        address trader = address(0xb0b);
        uint256 amountIn = 100;
        uint256 amountOut = 90;

        deal(address(tokenA), trader, amountIn);
        vm.prank(trader);
        tokenA.safeTransfer(address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(MockRouter.swap.selector, tokenA, tokenB, amountIn, amountOut);

        // expect
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(tokenA, tokenB, amountIn, amountOut);

        // when
        sut.executeSwap({
            tokenToSell: tokenA,
            tokenToBuy: tokenB,
            spender: address(mockRouter),
            amountIn: amountIn,
            minAmountOut: amountOut,
            router: address(mockRouter),
            swapBytes: swapBytes,
            to: trader
        });

        // then
        assertEq(tokenA.balanceOf(trader), 0);
        assertEq(tokenB.balanceOf(trader), amountOut);
    }

    function testMinOutputError() public {
        // given
        address trader = address(0xb0b);
        uint256 amountIn = 100;
        uint256 amountOut = 90;

        deal(address(tokenA), trader, amountIn);
        vm.prank(trader);
        tokenA.safeTransfer(address(sut), amountIn);

        bytes memory swapBytes = abi.encodeWithSelector(MockRouter.swap.selector, tokenA, tokenB, amountIn, amountOut - 1);

        // expect
        vm.expectRevert(abi.encodeWithSelector(InsufficientAmountOut.selector, amountOut, amountOut - 1));

        // when
        sut.executeSwap({
            tokenToSell: tokenA,
            tokenToBuy: tokenB,
            spender: address(mockRouter),
            amountIn: amountIn,
            minAmountOut: amountOut,
            router: address(mockRouter),
            swapBytes: swapBytes,
            to: trader
        });
    }

}

contract MockRouter is StdCheats {

    using SafeERC20 for IERC20;

    function swap(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn, uint256 amountOut) public {
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        deal(address(tokenOut), address(this), amountOut);
        tokenOut.safeTransfer(msg.sender, amountOut);
    }

}

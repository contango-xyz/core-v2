//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "../TestSetup.t.sol";

import "src/periphery/DineroSwap.sol";

contract DineroSwapTest is BaseTest {

    Env env;

    IWETH9 weth;
    IPirexEth pirexEth;
    IERC20 pxEth;
    IERC4626 autoPxEth;
    address trader = makeAddr("trader");

    DineroSwap sut;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(19_476_830);

        weth = IWETH9(address(env.token(WETH)));
        pirexEth = IPirexEth(0xD664b74274DfEB538d9baC494F3a4760828B02b0);
        pxEth = pirexEth.pxEth();
        autoPxEth = pirexEth.autoPxEth();

        sut = new DineroSwap(weth, pirexEth);
    }

    function test_buy() public {
        (uint256 pxAmount, uint256 apxAmount, uint256 feeAmount) = sut.quoteBuy(1 ether);

        uint256 amount = 1 ether;
        env.dealAndApprove(weth, trader, amount, address(sut));

        vm.prank(trader);
        sut.buy(amount);

        assertEqDecimal(pxAmount, 1e18, 18);
        assertEqDecimal(apxAmount, 0.985061349781751817e18, 18);
        assertEqDecimal(feeAmount, 0, 18);
        assertEqDecimal(weth.balanceOf(address(sut)), 0, 18);
        assertEqDecimal(autoPxEth.balanceOf(trader), apxAmount, 18);
    }

    function test_sell() public {
        (uint256 pxAmount, uint256 ethAmount, uint256 feeAmount) = sut.quoteSell(1e18);

        env.dealAndApprove(autoPxEth, trader, 1e18, address(sut));

        vm.prank(trader);
        sut.sell(1e18);

        assertEqDecimal(pxAmount, 1.015165197803728629e18, 18, "pxAmount");
        assertEqDecimal(ethAmount, 1.010089371814709986e18, 18, "ethAmount");
        assertEqDecimal(feeAmount, 0.005075825989018643e18, 18, "feeAmount");
        assertEqDecimal(weth.balanceOf(address(sut)), 0, 18);
        assertEqDecimal(autoPxEth.balanceOf(trader), 0, 18);
        assertEqDecimal(weth.balanceOf(trader), ethAmount, 18);
    }

}

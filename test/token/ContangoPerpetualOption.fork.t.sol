//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";

import { ContangoPerpetualOption, DIAOracleV2, SD59x18, intoUint256, sd, uMAX_SD59x18 } from "src/token/ContangoPerpetualOption.sol";
import { ContangoToken } from "src/token/ContangoToken.sol";

contract ContangoPerpetualOptionForkTest is BaseTest {

    DIAOracleV2 internal tangoOracle = DIAOracleV2(0x75A2b0ae73f657EB818eC84630FeB8ab3773f32F);

    ContangoPerpetualOption internal sut;

    ContangoToken internal tango = ContangoToken(TANGO_ADDRESS);
    IERC20 internal usdc = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    address internal minter = TREASURY;

    uint256 tangoPrice = 0.05656265e18;

    function setUp() public {
        vm.createSelectFork("arbitrum", 273_764_920);

        sut = new ContangoPerpetualOption(TREASURY, DIAOracleV2(tangoOracle), tango);
        usdc = sut.USDC();
    }

    function test_tangoPrice() public view {
        assertEqDecimal(sut.tangoPrice().intoUint256(), tangoPrice, 18, "tango price");
    }

    function test_previewExercise() public view {
        (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost) = sut.previewExercise(sd(10e18));

        assertEqDecimal(tangoPrice_.intoUint256(), tangoPrice, 18, "price");
        assertEqDecimal(discount.intoUint256(), 0.055307854157630834e18, 18, "discount");
        assertEqDecimal(discountedPrice.intoUint256(), 0.053434291203030882e18, 18, "redemption");
        assertEqDecimal(cost, 0.534343e6, 6, "cost");
    }

    function test_Fund() public {
        uint256 amount = 150_000_000e18;

        _fund(amount);

        assertEqDecimal(sut.totalSupply(), amount, 18, "totalSupply");
        assertEqDecimal(sut.balanceOf(TREASURY), sut.totalSupply(), 18, "TREASURY balance");
        assertEqDecimal(tango.balanceOf(address(sut)), sut.totalSupply(), 18, "tango balance");
    }

    function test_exercise_approval() public {
        _fund(10_000e18);

        address user = makeAddr("user");
        vm.prank(TREASURY);
        sut.transfer(user, 1000e18);
        deal(address(usdc), user, 100e6);
        vm.prank(user);
        usdc.approve(address(sut), 100e6);

        uint256 usdcTrasuryBalance = usdc.balanceOf(TREASURY);
        assertEqDecimal(sut.balanceOf(user), 1000e18, 18, "intial oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 100e6, 6, "intial usd balance");
        assertEqDecimal(tango.balanceOf(user), 0, 18, "intial tango balance");

        vm.prank(user);
        (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost) = sut.exercise(sd(100e18), sd(0.056e18));

        assertEqDecimal(tangoPrice_.intoUint256(), tangoPrice, 18, "price");
        assertEqDecimal(discount.intoUint256(), 0.055307854157630834e18, 18, "discount");
        assertEqDecimal(discountedPrice.intoUint256(), 0.053434291203030882e18, 18, "redemption");
        assertEqDecimal(cost, 5.34343e6, 6, "cost");

        assertEqDecimal(sut.balanceOf(user), 900e18, 18, "final oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 94.65657e6, 6, "final usd balance");
        assertEqDecimal(tango.balanceOf(user), 100e18, 18, "final tango balance");
        assertEqDecimal(usdc.balanceOf(TREASURY), usdcTrasuryBalance + cost, 6, "final usd balance");
    }

    function _fund(uint256 amount) internal {
        vm.startPrank(TREASURY);
        tango.mint(TREASURY, amount);
        tango.approve(address(sut), amount);
        sut.fund(amount);
        vm.stopPrank();
    }

}

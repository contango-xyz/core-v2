//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract GranaryMoneyMarketViewRewardsBugTest is Test {

    using ERC20Lib for *;

    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;

    MoneyMarketId internal constant mm = MM_GRANARY;
    address internal rewardsToken = 0xfD389Dc9533717239856190F42475d3f263a270d;

    function setUp() public {
        vm.createSelectFork("optimism", 114_681_102);

        contango = Contango(proxyAddress("ContangoProxy"));
        sut = new GranaryMoneyMarketView(
            contango,
            IPool(IPoolAddressesProviderV2(0xdDE5dC81e40799750B92079723Da2acAF9e1C6D6).getLendingPool()),
            IPoolDataProvider(0x9546F673eF71Ff666ae66d01Fd6E7C6Dae5a9995),
            IAaveOracle(IPoolAddressesProviderV2(0xdDE5dC81e40799750B92079723Da2acAF9e1C6D6).getPriceOracle()),
            IWETH9(0x4200000000000000000000000000000000000006),
            IAggregatorV2V3(0x13e3Ee699D1909E989722E753853AE30b17e08c5)
        );
    }

    function testRewards_ForPosition() public {
        positionId = PositionId.wrap(0x555344435745544800000000000000000fffffffff0000000000000000000128);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Granary Token", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "GRAIN", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.103751431015602366e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 277.302195694098124346e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.016736025875714102e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Granary Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "GRAIN", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.030354429397418568e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 277.302195694098124345e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.016736025875714102e18, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(0xC5aFc3a0F462C5a387393421b6A253204a3Be8D2);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient),
            borrowing[0].claimable + lending[0].claimable,
            IERC20(rewardsToken).decimals(),
            "Claimed rewards"
        );
    }

}

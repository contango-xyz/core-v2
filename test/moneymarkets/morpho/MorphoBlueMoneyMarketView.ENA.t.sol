//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../TestSetup.t.sol";

contract MorphoBlueMoneyMarketViewTest is Test {

    Contango internal contango;
    ContangoLens internal lens;

    ERC20Mock ena;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_589_549);

        ena = new ERC20Mock();

        contango = Contango(proxyAddress("ContangoProxy"));
        lens = ContangoLens(proxyAddress("ContangoLensProxy"));

        MorphoBlueMoneyMarket mm = new MorphoBlueMoneyMarket(
            MM_MORPHO_BLUE,
            contango,
            IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb),
            MorphoBlueReverseLookup(0xCafD6Aad286B881F793F68eAa77573AB7312949E),
            ena
        );

        MorphoBlueMoneyMarketView mmv = new MorphoBlueMoneyMarketView(
            MM_MORPHO_BLUE,
            "Morpho Blue",
            contango,
            IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb),
            MorphoBlueReverseLookup(0xCafD6Aad286B881F793F68eAa77573AB7312949E),
            IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
            ena
        );

        vm.startPrank(TIMELOCK_ADDRESS);
        lens.setMoneyMarketView(mmv);

        IMoneyMarket existentMoneyMarket = contango.positionFactory().moneyMarket(mm.moneyMarketId());
        UpgradeableBeacon beacon = ImmutableBeaconProxy(payable(address(existentMoneyMarket))).__beacon();
        beacon.upgradeTo(address(mm));

        vm.stopPrank();
    }

    function testRewards_ENA() public {
        PositionId positionId = PositionId.wrap(0x7355534465555344540000000000000008ffffffff000000000d000000000037);

        (Reward[] memory borrowing, Reward[] memory lending) = lens.rewards(positionId);
        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        // Simulate an airdrop of ENA tokens
        ena.mint(address(contango.positionFactory().moneyMarket(positionId)), 10e18);

        (borrowing, lending) = lens.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), address(ena), "Lend reward[0] token");
        assertEq(lending[0].token.name, "ERC20Mock", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "E20M", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 10e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(0x2a4300dA64A43c32E6Eac6Dd1e171502ba48dd89);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(ena.balanceOf(recipient), lending[0].claimable, ena.decimals(), "Claimed ENA rewards");
    }

}

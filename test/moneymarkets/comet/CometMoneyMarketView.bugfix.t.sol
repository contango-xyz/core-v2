//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract CometMoneyMarketViewBugfixTest is Test {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_RewardsOverflow() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x777374455448574554480000000000000effffffff0000000002000000000000);

        vm.createSelectFork("mainnet", 19_639_119);
        vm.expectRevert(IComet.BadAsset.selector);
        contangoLens.metaData(positionId);

        // replace CometMoneyMarketView
        vm.etch(
            0x0aeFf85B59FB641C2f60cdd396294446CB93e27F,
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                    _nativeUsdOracle: IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
                    _reverseLookup: CometReverseLookup(0x94e46A68814D09a3131221eec190512a374e6BF1),
                    _cometRewards: ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40),
                    _compOracle: IAggregatorV2V3(0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5)
                })
            ).code
        );

        contangoLens.metaData(positionId);
    }

    function testBugFix_LiquidityOverflow() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x574554485553446243000000000000000effffffff0000000001000000000000);

        vm.createSelectFork("base", 13_278_883);
        vm.expectRevert();
        contangoLens.metaData(positionId);

        // replace CometMoneyMarketView
        vm.etch(
            0x163046ca3A4179038e3A8c07915D0ACC7F5081Bc,
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0x4200000000000000000000000000000000000006),
                    _nativeUsdOracle: IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                    _reverseLookup: CometReverseLookup(0xD915a274Dfc25535fe64bEAa9F1Ce032eb341945),
                    _cometRewards: ICometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1),
                    _compOracle: IAggregatorV2V3(0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428)
                })
            ).code
        );

        contangoLens.metaData(positionId);
    }

    function testEthMarketsPricingFuckup_Ethereum() public {
        IERC20 ezETH = IERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        CometMoneyMarketView sut = CometMoneyMarketView(0x1B51B89B6c3f855cEb11710001909EC5E01a7951);
        positionId = PositionId.wrap(0x657a45544857455448000000000000000effffffff0000000002000000000268);

        vm.createSelectFork("mainnet", 20_336_106);

        Prices memory prices = sut.prices(positionId);
        assertEqDecimal(prices.collateral, 1.01463976e8, 8, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, 8, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
        assertEqDecimal(sut.priceInNativeToken(ezETH), 0.000297441008741388e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(weth), 1.0e18, 18, "Quote price in native token");
        assertApproxEqAbsDecimal(sut.priceInUSD(ezETH), 1.014639759999997958e18, 1, 18, "Base price in USD");
        assertApproxEqAbsDecimal(sut.priceInUSD(weth), 3411.23022778e18, 1, 18, "Quote price in USD");

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), 0xc00e94Cb662C3520282E6f5717214004A7f26888, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.000000000009182307e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.008604e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 51.30993e18, 18, "Borrow reward[0] usdPrice");

        // replace CometMoneyMarketView
        vm.etch(
            address(sut),
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                    _nativeUsdOracle: IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
                    _reverseLookup: CometReverseLookup(0x94e46A68814D09a3131221eec190512a374e6BF1),
                    _cometRewards: ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40),
                    _compOracle: IAggregatorV2V3(0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5)
                })
            ).code
        );

        prices = sut.prices(positionId);
        assertEqDecimal(prices.collateral, 1.01463976e8, 8, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, 8, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
        assertEqDecimal(sut.priceInNativeToken(ezETH), 1.014639759997231341e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(weth), 1.0e18, 18, "Quote price in native token");
        assertApproxEqAbsDecimal(sut.priceInUSD(ezETH), 3461.169819609999999528e18, 1, 18, "Base price in USD");
        assertApproxEqAbsDecimal(sut.priceInUSD(weth), 3411.23022778e18, 1, 18, "Quote price in USD");

        (borrowing, lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), 0xc00e94Cb662C3520282E6f5717214004A7f26888, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.002697398280272435e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.008604e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 51.30993e18, 18, "Borrow reward[0] usdPrice");
    }

    function testEthMarketsPricingFuckup_Base() public {
        IERC20 cbETH = IERC20(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
        IERC20 weth = IERC20(0x4200000000000000000000000000000000000006);

        CometMoneyMarketView sut = CometMoneyMarketView(0x87F3230Eef54c5513B04395c5C00AF9aF48d90AA);
        positionId = PositionId.wrap(0x636245544857455448000000000000000effffffff0000000002000000000c2a);

        vm.createSelectFork("base", 17_277_469);

        Prices memory prices = sut.prices(positionId);
        assertEqDecimal(prices.collateral, 1.07651e8, 8, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, 8, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
        assertEqDecimal(sut.priceInNativeToken(cbETH), 1.076509999997962641e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(weth), 1.0e18, 18, "Quote price in native token");
        assertApproxEqAbsDecimal(sut.priceInUSD(cbETH), 3698.696418259999997737e18, 1, 18, "Base price in USD");
        assertApproxEqAbsDecimal(sut.priceInUSD(weth), 3435.8217e18, 1, 18, "Quote price in USD");

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), 0x9e1028F5F1D5eDE59748FFceE5532509976840E0, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.000000000025970092e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.000013e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 52.19117694e18, 18, "Borrow reward[0] usdPrice");

        // replace CometMoneyMarketView
        vm.etch(
            address(sut),
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0x4200000000000000000000000000000000000006),
                    _nativeUsdOracle: IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                    _reverseLookup: CometReverseLookup(0xD915a274Dfc25535fe64bEAa9F1Ce032eb341945),
                    _cometRewards: ICometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1),
                    _compOracle: IAggregatorV2V3(0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428)
                })
            ).code
        );

        prices = sut.prices(positionId);
        assertEqDecimal(prices.collateral, 1.07651e8, 8, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, 8, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
        assertEqDecimal(sut.priceInNativeToken(cbETH), 1.076509999997962641e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(weth), 1.0e18, 18, "Quote price in native token");
        assertApproxEqAbsDecimal(sut.priceInUSD(cbETH), 3698.696418259999997737e18, 1, 18, "Base price in USD");
        assertApproxEqAbsDecimal(sut.priceInUSD(weth), 3435.8217e18, 1, 18, "Quote price in USD");

        (borrowing, lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), 0x9e1028F5F1D5eDE59748FFceE5532509976840E0, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.0076073131140853e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.000013e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 52.19117694e18, 18, "Borrow reward[0] usdPrice");
    }

}

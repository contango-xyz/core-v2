//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

contract MorphoBlueMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using MarketParamsLib for MarketParams;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    IMorpho internal morpho;
    MorphoBlueReverseLookup internal reverseLookup;

    MoneyMarketId internal constant mmId = MM_MORPHO_BLUE;

    Payload internal payload;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_919_243);

        contango = env.contango();
        morpho = env.morpho();

        MorphoBlueMoneyMarket mm = MorphoBlueMoneyMarket(address(env.positionFactory().moneyMarket(mmId)));
        reverseLookup = mm.reverseLookup();

        sut = env.contangoLens().moneyMarketView(mmId);

        MorphoOracleMock oracle = new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC));
        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: oracle,
            irm: IIrm(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            lltv: 0.86e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        payload = reverseLookup.setMarket(params.id());
        vm.stopPrank();

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = encode(instrument.symbol, mmId, PERP, 0, payload);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public view {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e24, 24, "Collateral price");
        assertEqDecimal(prices.debt, 1e24, 24, "Debt price");
        assertEq(prices.unit, 1e24, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 100_000e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liq) = sut.liquidity(positionId);

        assertEqDecimal(liq, instrument.base.totalSupply(), instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.86e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.86e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.01005002869698448e18, 18, "Borrowing rate");
        assertEq(lendingRate, 0, "Lending rate");
    }

}

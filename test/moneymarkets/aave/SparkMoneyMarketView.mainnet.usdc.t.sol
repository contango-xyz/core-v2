//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract SparkMoneyMarketViewUSDCTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    IPool internal pool;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_SPARK;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_292_459);

        contango = env.contango();

        sut = env.contangoLens().moneyMarketView(mm);
        pool = AaveMoneyMarketView(address(sut)).pool();
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: env.erc20(DAI),
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition_long() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition_short() public {
        instrument = env.createInstrument(env.erc20(USDC), env.erc20(WETH));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10_000e6,
            cashflow: 4 ether,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10_000e6, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6 ether, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e8, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
    }

    function testBaseQuoteRate() public {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(baseQuoteRate, 1000e6, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
    }

    function testPriceInUSD() public {
        assertEqDecimal(sut.priceInUSD(instrument.base), 1000e18, 18, "Base price in USD");
        assertEqDecimal(sut.priceInUSD(instrument.quote), 1e18, 18, "Quote price in USD");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 32_003_291.597896e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testBorrowingLiquidity_IsolationMode() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(WETH), env.token(USDC), mm);
        (uint256 normalLiquidity,) = sut.liquidity(positionId);
        (,, positionId) = env.createInstrumentAndPositionId(env.token(GNO), env.token(USDC), mm);
        (uint256 isolationModeCappedLiquidity,) = sut.liquidity(positionId);
        // (,,positionId) = env.createInstrumentAndPositionId(env.token(ARB), env.token(USDC), mm);
        // (uint256 isolationModeUncappedLiquidity,) = sut.liquidity(positionId);

        assertEqDecimal(normalLiquidity, 32_003_291.597896e6, 6, "Normal liquidity");
        assertEqDecimal(isolationModeCappedLiquidity, 2_502_375.66e6, 6, "Isolation mode capped liquidity");
        // assertEqDecimal(isolationModeUncappedLiquidity, 32_003_291.5978960e6, 6, "Isolation mode uncapped liquidity");
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId);
        assertEqDecimal(liquidity, type(uint256).max, instrument.baseDecimals, "Lending liquidity");
    }

    // Only asset that's not allowed is USDC, but we handle that internally
    // function testLendingLiquidity_AssetNotAllowedAsCollateral() public {
    //     (, uint256 lendingLiquidity) = sut.liquidity(positionId, env.token(LUSD), env.token(USDC));
    //     assertEqDecimal(lendingLiquidity, 0, 18, "No lending liquidity");
    // }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_NewPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(RETH));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.9e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.93e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(RETH));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 8e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.9e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.93e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(WETH), env.token(USDC), mm);
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.053790164207174267e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.016037973502695556e18, 18, "Lending rate");

        (,, positionId) = env.createInstrumentAndPositionId(env.token(USDC), env.token(WETH), mm);
        (borrowingRate, lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.028456772686872275e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.05e18, 18, "Lending rate");
    }

}

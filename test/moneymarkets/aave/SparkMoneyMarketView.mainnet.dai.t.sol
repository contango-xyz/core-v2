//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract SparkMoneyMarketViewDAITest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    SparkMoneyMarketView internal sut;
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

        sut =
        new SparkMoneyMarketView(MM_SPARK, env.sparkAddressProvider(), contango.positionFactory(),env.token(DAI), ISDAI(address(env.token(SDAI))), env.token(USDC));
        pool = IPool(env.sparkAddressProvider().getPool());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(DAI));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
    }

    function testBalances_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition_long() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e18, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition_short() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(WETH));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10_000e18,
            cashflow: 4 ether,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);

        assertApproxEqRelDecimal(balances.collateral, 10_000e18, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6 ether, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId, instrument.base, instrument.quote);

        assertEqDecimal(prices.collateral, 1000e8, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e8, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e8, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(beforePosition, 32_003_291.597896510043760325e18, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testBorrowingLiquidity_IsolationMode() public {
        (uint256 normalLiquidity,) = sut.liquidity(positionId, env.token(WETH), env.token(DAI));
        (uint256 isolationModeCappedLiquidity,) = sut.liquidity(positionId, env.token(GNO), env.token(DAI));
        // (uint256 isolationModeUncappedLiquidity,) = sut.liquidity(positionId, env.token(ARB), env.token(DAI));

        assertEqDecimal(normalLiquidity, 32_003_291.597896510043760325e18, 18, "Normal liquidity");
        assertEqDecimal(isolationModeCappedLiquidity, 2_502_375.66e18, 18, "Isolation mode capped liquidity");
        // assertEqDecimal(isolationModeUncappedLiquidity, 32_003_291.597896510043760325e18, 18, "Isolation mode uncapped liquidity");
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId, instrument.base, instrument.quote);
        assertEqDecimal(liquidity, type(uint256).max, instrument.baseDecimals, "Lending liquidity");
    }

    // Only asset that's not allowed is USDC, but we handle that internally
    // function testLendingLiquidity_AssetNotAllowedAsCollateral() public {
    //     (, uint256 lendingLiquidity) = sut.liquidity(positionId, env.token(LUSD), env.token(DAI));
    //     assertEqDecimal(lendingLiquidity, 0, 18, "No lending liquidity");
    // }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

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

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_NewPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(RETH));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SPARK, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

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

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.9e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.93e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId, instrument.base, instrument.quote);

        assertEqDecimal(borrowingRate, 0.053790164207174267e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.016037973502695556e18, 18, "Lending rate");

        (borrowingRate, lendingRate) = sut.rates(positionId, env.token(DAI), env.token(WETH));

        assertEqDecimal(borrowingRate, 0.028456772686872275e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.05e18, 18, "Lending rate");
    }

}

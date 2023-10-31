//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract AaveMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    AaveMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    IPool internal pool;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_AAVE;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(137_805_880);

        contango = env.contango();

        sut = new AaveMoneyMarketView(MM_AAVE, env.aaveAddressProvider(), contango.positionFactory());
        pool = IPool(env.aaveAddressProvider().getPool());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
    }

    function testBalances_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
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
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(beforePosition, 2_774_841.625772e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testBorrowingLiquidity_IsolationMode() public {
        (uint256 normalLiquidity,) = sut.liquidity(positionId, env.token(WETH), env.token(USDC));
        (uint256 isolationModeCappedLiquidity,) = sut.liquidity(positionId, env.token(USDT), env.token(USDC));
        (uint256 isolationModeUncappedLiquidity,) = sut.liquidity(positionId, env.token(ARB), env.token(USDC));

        assertEqDecimal(normalLiquidity, 2_774_841.625772e6, 6, "Normal liquidity");
        assertEqDecimal(isolationModeCappedLiquidity, 2_481_926.26e6, 6, "Isolation mode capped liquidity");
        assertEqDecimal(isolationModeUncappedLiquidity, 2_774_841.625772e6, 6, "Isolation mode uncapped liquidity");
    }

    function testLendingLiquidity() public {
        (, uint256 beforePosition) = sut.liquidity(positionId, instrument.base, instrument.quote);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (, uint256 afterPosition) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(beforePosition, 28_060.92480318214521948e18, instrument.baseDecimals, "Lending liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 10 ether, TOLERANCE, instrument.baseDecimals, "Lending liquidity delta");
    }

    function testLendingLiquidity_AssetNotAllowedAsCollateral() public {
        (, uint256 lendingLiquidity) = sut.liquidity(positionId, env.token(LUSD), env.token(USDC));
        assertEqDecimal(lendingLiquidity, 0, 18, "No lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.85e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.85e18, 18, "Liquidation threshold");
    }

    function testThresholds_NewPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(USDC));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.93e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.95e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(USDC));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10_000e18,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.93e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.95e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId, instrument.base, instrument.quote);

        assertEqDecimal(borrowingRate, 0.119753936034257584e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.011141821300488233e18, 18, "Lending rate");
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract AaveV2MoneyMarketViewPolygonTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    IPool internal pool;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_AAVE_V2;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Polygon);
        env.init();

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

        // USDC / ETH - 18 decimals
        env.spotStub().stubChainlinkPrice(0.001e18, 0xefb7e6be8356cCc6827799B6A7348eE674A80EaE);
        // MATIC / ETH - 18 decimals
        env.spotStub().stubChainlinkPrice(0.002e18, 0x327e23A4855b6F663a28c5161541d69Af8973302);
        env.spotStub().stubChainlinkPrice(2e8, address(env.erc20(WMATIC).chainlinkUsdOracle));

        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
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

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId);

        // V2 common ccy is ETH
        assertEqDecimal(prices.collateral, 1e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testBaseQuoteRate() public {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(baseQuoteRate, 1000e6, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public {
        // MATIC / USD = 2, so 1 ETH = 500 MATIC
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 500e18, 18, "Base price in native token");
        // MATIC / USD = 2, so 1 USDC = 0.5 MATIC
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.5e18, 18, "Quote price in native token");
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

        assertEqDecimal(beforePosition, 10_531_495.462401e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 208_987.425239629259759118e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testLendingLiquidity_AssetNotAllowedAsCollateral() public {
        (,, positionId) = env.createInstrumentAndPositionId(IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F), env.token(USDC), mm);
        (, uint256 lendingLiquidity) = sut.liquidity(positionId);
        assertEqDecimal(lendingLiquidity, 0, 18, "No lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.031433048549585358e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.000628199858035208e18, 18, "Lending rate");
    }

}

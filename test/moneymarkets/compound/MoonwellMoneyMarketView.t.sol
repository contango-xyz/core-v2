//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract MoonwellMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_MOONWELL;

    address internal rewardsToken;
    address internal rewardsToken2;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Base);
        env.init(7_250_859);

        contango = env.contango();

        sut = env.contangoLens().moneyMarketView(mm);
        rewardsToken = address(env.moonwellToken());
        rewardsToken2 = address(env.token(USDCn));

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ValidPosition() public {
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

        assertEqDecimal(prices.collateral, 1000e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
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

    function testBorrowingLiquidity_WETHUSDC() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 273_452.432728e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e6 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testLendingLiquidity_WETHUSDC() public {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 4564.190776179833450445e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testBorrowingLiquidity_USDCWETH() public {
        Symbol symbol;
        (symbol,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            symbol: symbol,
            mm: mm,
            quantity: 10_000e6,
            cashflow: 4 ether,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 1768.768384259168597137e18, 18, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6 ether * 0.95e18 / 1e18, TOLERANCE, 18, "Borrowing liquidity delta");
    }

    function testLendingLiquidity_USDCWETH() public {
        (,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 3_560_347.199676e6, 6, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.81e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.81e18, 18, "Liquidation threshold");
    }

    function testThresholds_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.81e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.81e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.054576395814888128e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.018460234250925842e18, 18, "Lending rate");
    }

    function testRewards_WETHUSDC() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2028e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken2, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "USD Coin", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "USDC", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 6, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e6, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.000000000000000027e18, 18, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.9999999999999984e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "WELL", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "WELL", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.030449875325309134e18, 18, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.0056588243333232e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken2, "Lend reward[1] token");
        assertEq(lending[1].token.name, "USD Coin", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "USDC", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 6, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e6, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.014350953256418171e18, 18, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.9999999999999984e18, 18, "Lend reward[1] usdPrice");
    }

    function testRewards_USDCWETH() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2028e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        // Use native USDC instead as USDbC has no rewards as of this block
        (,, positionId) = env.createInstrumentAndPositionId(IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913), instrument.base, mm);
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken2, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "USD Coin", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "USDC", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 6, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e6, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.00000380812069811e18, 18, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.9999999999999984e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "WELL", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "WELL", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.04482368862634881e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.0056588243333232e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken2, "Lend reward[1] token");
        assertEq(lending[1].token.name, "USD Coin", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "USDC", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 6, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e6, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.021122983179844172e18, 18, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.9999999999999984e18, 18, "Lend reward[1] usdPrice");
    }

    function testRewards_ForPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(5 days);

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(5 days);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken2, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "USD Coin", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "USDC", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 6, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e6, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.000000000000000026e18, 18, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.000916e6, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "WELL", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "WELL", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.030340046969788287e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 611.234147002709485315e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.0027903473044e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken2, "Lend reward[1] token");
        assertEq(lending[1].token.name, "USD Coin", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "USDC", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 6, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e6, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.028998760191050826e18, 18, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 1.630155e6, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 1e18, 18, "Lend reward[1] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertApproxEqRelDecimal(
            IERC20(rewardsToken).balanceOf(recipient),
            lending[0].claimable,
            0.00001e18,
            IERC20(rewardsToken).decimals(),
            "Claimed rewards 1"
        );
        assertApproxEqRelDecimal(
            IERC20(rewardsToken2).balanceOf(recipient), lending[1].claimable, 0.01e18, IERC20(rewardsToken2).decimals(), "Claimed rewards 2"
        );
    }

}

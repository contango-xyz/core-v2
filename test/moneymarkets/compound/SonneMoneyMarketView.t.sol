//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract SonneMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Env internal env;
    CompoundMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    IComptroller internal comptroller;

    MoneyMarketId internal constant mm = MM_SONNE;

    address internal rewardsToken;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init(112_234_650);

        contango = env.contango();

        sut = CompoundMoneyMarketView(address(env.contangoLens().moneyMarketView(mm)));
        rewardsToken = address(env.compoundComptroller().getCompAddress());
        comptroller = env.compoundComptroller();

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SONNE, PERP, 0);
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

    function testPrices() public view {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e18, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testBaseQuoteRate() public view {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(baseQuoteRate, 1000e6, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
    }

    function testPriceInUSD() public view {
        assertEqDecimal(sut.priceInUSD(instrument.base), 1000e18, 18, "Base price in USD");
        assertEqDecimal(sut.priceInUSD(instrument.quote), 1e18, 18, "Quote price in USD");
    }

    function testBalancesUSD() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balancesUSD(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10_000e18, TOLERANCE, 18, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e18, TOLERANCE, 18, "Debt balance");
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

        assertEqDecimal(beforePosition, 2_111_565.30455e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e6 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
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

        assertEqDecimal(beforePosition, 1044.462258323656137782 ether, 18, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6 ether * 0.95e18 / 1e18, TOLERANCE, 18, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 48_748.536219336686435387e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SONNE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.75e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.75e18, 18, "Liquidation threshold");
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

        assertEqDecimal(ltv, 0.75e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.75e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.086314312788434496e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.025701731420958887e18, 18, "Lending rate");
    }

    function testRewards_WETHUSDC() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2043e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Sonne", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "SONNE", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.021133926292836797e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.086204e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Sonne", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "SONNE", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.002356340699747709e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.086204e18, 18, "Lend reward[0] usdPrice");
    }

    function testRewards_USDCWETH() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2043e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Sonne", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "SONNE", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.023865330280930601e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.086204e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Sonne", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "SONNE", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.002487799109488814e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.086204e18, 18, "Lend reward[0] usdPrice");
    }

    function testRewards_ForPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Sonne", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "SONNE", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.021037442007621931e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 162.206762634987937318e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.086204e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Sonne", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "SONNE", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.004782155524771788e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 87.270084193708328157e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.086204e18, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient),
            borrowing[0].claimable + lending[0].claimable,
            IERC20(rewardsToken).decimals(),
            "Claimed rewards"
        );
    }

    function testAvailableActions_HappyPath() public {
        AvailableActions[] memory availableActions = sut.availableActions(positionId);

        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_MintPaused() public {
        ICToken cToken = sut._cToken(instrument.base);
        vm.prank(comptroller.pauseGuardian());
        comptroller._setMintPaused(cToken, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BorrowPaused() public {
        ICToken cToken = sut._cToken(instrument.quote);
        vm.prank(comptroller.pauseGuardian());
        comptroller._setBorrowPaused(cToken, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

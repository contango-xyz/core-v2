//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract CompoundMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Env internal env;
    CompoundMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    IComptroller internal comptroller;

    MoneyMarketId internal constant mm = MM_COMPOUND;

    address internal rewardsToken;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;
    address internal oracle;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(19_377_178);

        contango = env.contango();

        sut = CompoundMoneyMarketView(address(env.contangoLens().moneyMarketView(mm)));
        comptroller = env.compoundComptroller();
        rewardsToken = address(comptroller.getCompAddress());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(DAI));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        oracle = comptroller.oracle();
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(1000e18)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643),
            abi.encode(1e18)
        );

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
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e18, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");

        (,, positionId) = env.createInstrumentAndPositionId(env.token(WBTC), env.token(USDC), mm);
        prices = sut.prices(positionId);
        assertEqDecimal(prices.collateral, 66_531.66e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testBaseQuoteRate() public view {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(baseQuoteRate, 1000e18, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
    }

    function testPriceInUSD() public view {
        assertEqDecimal(sut.priceInUSD(instrument.base), 1000e18, 18, "Base price in USD");
        assertEqDecimal(sut.priceInUSD(instrument.quote), 1e18, 18, "Quote price in USD");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 33_467_030.840255398847414579e18, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e18 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testBorrowingLiquidity_ETH() public {
        (,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (uint256 liq,) = sut.liquidity(positionId);

        assertEqDecimal(liq, 97_075.371244188495039679e18, instrument.baseDecimals, "Borrowing liquidity");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 3_046_116.926082053596270551e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.101347824921932373e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.000433411744398195e18, 18, "Lending rate");
    }

    function testRewards_WETHDAI() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2043e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(2043e18)
        );

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.012683278843492036e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 87.05231007e18, 18, "Borrow reward[0] usdPrice");
    }

    function testRewards_DAIWETH() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2043e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(2043e18)
        );

        (,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Compound", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "COMP", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.010579925694835915e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 87.05231007e18, 18, "Lend reward[0] usdPrice");
    }

    function testRewards_ForPosition_WETHDAI() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);
        vm.roll(block.number + 15 * 24 * 60 * 60 / 12);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.012681987022331147e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.035921680776340404e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 87.05231007e18, 18, "Borrow reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient), borrowing[0].claimable, IERC20(rewardsToken).decimals(), "Claimed rewards"
        );
    }

    function testRewards_ForPosition_DAIWETH() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(WETH));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10_000e18,
            cashflow: 4 ether,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);
        vm.roll(block.number + 15 * 24 * 60 * 60 / 12);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Compound", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "COMP", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.010578471288698814e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0.049939133889297868e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 87.05231007e18, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(IERC20(rewardsToken).balanceOf(recipient), lending[0].claimable, IERC20(rewardsToken).decimals(), "Claimed rewards");
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

    function testAvailableActions_CantBeCollateral() public {
        instrument = env.createInstrument(env.erc20(USDT), env.erc20(WETH));
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

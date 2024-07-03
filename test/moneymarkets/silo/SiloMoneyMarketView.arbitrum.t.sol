//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract SiloMoneyMarketViewArbitrumTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Env internal env;
    SiloMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_SILO;

    address internal rewardsToken;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(195_468_081);

        contango = env.contango();

        sut = SiloMoneyMarketView(address(env.contangoLens().moneyMarketView(mm)));
        rewardsToken = 0x0341C0C0ec423328621788d4854119B97f44E391;

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        env.spotStub().stubChainlinkPrice(1.1e8, address(env.erc20(ARB).chainlinkUsdOracle));

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

    function testBalances_PauseGlobal() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(address(silo.siloRepository()), abi.encodeWithSelector(ISiloRepository.isPaused.selector), abi.encode(true));

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_PauseBase() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.base),
            abi.encode(true)
        );

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_PauseQuote() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.quote),
            abi.encode(true)
        );

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_PauseBaseAndQuote() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.base),
            abi.encode(true)
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.quote),
            abi.encode(true)
        );

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public view {
        Prices memory prices = sut.prices(positionId);

        // Silo's oracle is ETH based
        assertEqDecimal(prices.collateral, 1e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "Debt price");
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

        assertEqDecimal(beforePosition, 907_875.067674e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 220_278.764722907948283565e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.85e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.9e18, 18, "Liquidation threshold");
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

        assertEqDecimal(ltv, 0.85e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.9e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.156216303580176e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.01812759217056907e18, 18, "Lending rate");
    }

    function testRewards_NoPosition() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubChainlinkPrice(1.091e8, address(env.erc20(ARB).chainlinkUsdOracle));
        env.spotStub().stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
        // Silo's oracle is ETH based, so we need a live ETH price
        env.spotStub().stubChainlinkPrice(2168e8, address(env.erc20(WETH).chainlinkUsdOracle));

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Silo Governance Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "Silo", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.027967232284421903e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.065967117740569448e18, 18, "Lend reward[0] usdPrice");
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

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Silo Governance Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "Silo", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.028320996985557908e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 370.746701038588359402e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.030957945706026e18, 18, "Lend reward[0] usdPrice");

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

    function testAvailableActions_BaseNonActive() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getRemovedBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        silo.syncBridgeAssets();

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteNonActive() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getRemovedBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        silo.syncBridgeAssets();

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_PauseGlobal() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        silo.syncBridgeAssets();

        vm.mockCall(address(silo.siloRepository()), abi.encodeWithSelector(ISiloRepository.isPaused.selector), abi.encode(true));

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_PauseBase() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        silo.syncBridgeAssets();

        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.base),
            abi.encode(true)
        );

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_PauseQuote() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        silo.syncBridgeAssets();

        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.quote),
            abi.encode(true)
        );

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_PauseBaseAndQuote() public {
        ISilo silo = sut.getSilo(instrument.base, instrument.quote);
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.base))
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.getBridgeAssets.selector),
            abi.encode(toArray(instrument.quote))
        );
        silo.syncBridgeAssets();

        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.base),
            abi.encode(true)
        );
        vm.mockCall(
            address(silo.siloRepository()),
            abi.encodeWithSelector(ISiloRepository.isSiloPaused.selector, silo, instrument.quote),
            abi.encode(true)
        );

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

}

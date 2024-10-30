//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

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

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(195_468_081);

        contango = env.contango();

        sut = SiloMoneyMarketView(address(env.contangoLens().moneyMarketView(mm)));

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        stubChainlinkPrice(1.1e8, address(env.erc20(ARB).chainlinkUsdOracle));

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

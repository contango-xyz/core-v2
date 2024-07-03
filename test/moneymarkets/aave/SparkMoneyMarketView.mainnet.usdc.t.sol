//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./IPoolConfigurator.sol";

import "../AbstractMMV.t.sol";

contract SparkMoneyMarketViewDAITest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IPool internal pool;
    IPoolConfigurator internal poolConfigurator;

    constructor() AbstractMarketViewTest(MM_SPARK) { }

    function setUp() public {
        super.setUp(Network.Mainnet, 18_292_459);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfigurator(env.sparkAddressProvider().getPoolConfigurator());

        vm.mockCall(
            env.sparkAddressProvider().getACLManager(), abi.encodeWithSignature("isPoolAdmin(address)", address(this)), abi.encode(true)
        );

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: env.erc20(DAI),
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
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

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
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

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);
        assertEqDecimal(liquidity, type(uint256).max, instrument.baseDecimals, "Lending liquidity");
    }

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

        assertEqDecimal(borrowingRate, 0.055258964761166048e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.016166914046988865e18, 18, "Lending rate");

        (,, positionId) = env.createInstrumentAndPositionId(env.token(USDC), env.token(WETH), mm);
        (borrowingRate, lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.028864393507594878e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.05e18, 18, "Lending rate");
    }

    function testAvailableActions_BaseFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.base, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteFrozen() public {
        poolConfigurator.setReserveFreeze(env.token(DAI), true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BothFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.base, true);
        poolConfigurator.setReserveFreeze(env.token(DAI), true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BasePaused() public {
        poolConfigurator.setReservePause(instrument.base, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuotePaused() public {
        poolConfigurator.setReservePause(env.token(DAI), true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_BothPaused() public {
        poolConfigurator.setReservePause(instrument.base, true);
        poolConfigurator.setReservePause(env.token(DAI), true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertEq(availableActions.length, 0, "No available actions");
    }

    function testAvailableActions_QuoteBorrowingDisabled() public {
        poolConfigurator.setReserveStableRateBorrowing(env.token(DAI), false);
        poolConfigurator.setReserveBorrowing(env.token(DAI), false);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

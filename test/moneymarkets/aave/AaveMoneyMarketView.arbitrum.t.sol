//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./IPoolConfigurator.sol";
import "../AbstractMMV.t.sol";

contract AaveMoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IPool internal pool;
    IPoolConfigurator internal poolConfigurator;

    constructor() AbstractMarketViewTest(MM_AAVE) { }

    function setUp() public {
        super.setUp(Network.Arbitrum, 137_805_880);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfigurator(env.aaveAddressProvider().getPoolConfigurator());

        vm.mockCall(
            env.aaveAddressProvider().getACLManager(), abi.encodeWithSignature("isPoolAdmin(address)", address(this)), abi.encode(true)
        );
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

        assertEqDecimal(beforePosition, 2_774_841.625772e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testBorrowingLiquidity_IsolationMode() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(WETH), env.token(USDC), mm);
        (uint256 normalLiquidity,) = sut.liquidity(positionId);
        (,, positionId) = env.createInstrumentAndPositionId(env.token(USDT), env.token(USDC), mm);
        (uint256 isolationModeCappedLiquidity,) = sut.liquidity(positionId);
        (,, positionId) = env.createInstrumentAndPositionId(env.token(ARB), env.token(USDC), mm);
        (uint256 isolationModeUncappedLiquidity,) = sut.liquidity(positionId);

        assertEqDecimal(normalLiquidity, 2_774_841.625772e6, 6, "Normal liquidity");
        assertEqDecimal(isolationModeCappedLiquidity, 2_481_926.26e6, 6, "Isolation mode capped liquidity");
        assertEqDecimal(isolationModeUncappedLiquidity, 2_774_841.625772e6, 6, "Isolation mode uncapped liquidity");
    }

    function testLendingLiquidity() public {
        (, uint256 beforePosition) = sut.liquidity(positionId);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (, uint256 afterPosition) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 28_060.531239852040906233e18, instrument.baseDecimals, "Lending liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 10 ether, TOLERANCE, instrument.baseDecimals, "Lending liquidity delta");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

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

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.85e18, 18, "Liquidation threshold");
    }

    function testThresholds_NewPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(USDC));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

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

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.93e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.95e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.127197309926195207e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.01120395057855792e18, 18, "Lending rate");
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
        poolConfigurator.setReserveFreeze(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BothFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.base, true);
        poolConfigurator.setReserveFreeze(instrument.quote, true);

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
        poolConfigurator.setReservePause(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_BothPaused() public {
        poolConfigurator.setReservePause(instrument.base, true);
        poolConfigurator.setReservePause(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertEq(availableActions.length, 0, "No available actions");
    }

    function testAvailableActions_BaseCollateralDisabled() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(LUSD), env.token(USDC), mm);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteBorrowingDisabled() public {
        poolConfigurator.setReserveStableRateBorrowing(instrument.quote, false);
        poolConfigurator.setReserveBorrowing(instrument.quote, false);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

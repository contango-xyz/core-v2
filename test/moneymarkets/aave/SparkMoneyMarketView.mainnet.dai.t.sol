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

    IERC20 internal wstEth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    constructor() AbstractMarketViewTest(MM_SPARK) { }

    function setUp() public {
        super.setUp(Network.Mainnet, 19_189_829, WETH, 1000e8, DAI, 1e8, 8);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfigurator(env.sparkAddressProvider().getPoolConfigurator());

        vm.mockCall(
            env.sparkAddressProvider().getACLManager(), abi.encodeWithSignature("isPoolAdmin(address)", address(this)), abi.encode(true)
        );
    }

    function testBalances_ExistingPosition_long() public {
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

    function testBalances_ExistingPosition_short() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(WETH));

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10_000e18,
            cashflow: 4 ether,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10_000e18, TOLERANCE, instrument.baseDecimals, "Collateral balance");
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
            cashflow: 4000e18,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 29_983_128.930477075804749644e18, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testBorrowingLiquidity_IsolationMode() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(WETH), env.token(DAI), mm);
        (uint256 normalLiquidity,) = sut.liquidity(positionId);
        (,, positionId) = env.createInstrumentAndPositionId(env.token(GNO), env.token(DAI), mm);
        (uint256 isolationModeCappedLiquidity,) = sut.liquidity(positionId);
        // (,,positionId) = env.createInstrumentAndPositionId(env.token(ARB), env.token(DAI), mm);
        // (uint256 isolationModeUncappedLiquidity,) = sut.liquidity(positionId);

        assertEqDecimal(normalLiquidity, 29_983_128.930477075804749644e18, 18, "Normal liquidity");
        assertEqDecimal(isolationModeCappedLiquidity, 5_000_000.0e18, 18, "Isolation mode capped liquidity");
        // assertEqDecimal(isolationModeUncappedLiquidity, 32_003_291.597896510043760325e18, 18, "Isolation mode uncapped liquidity");
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
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.064594285929201427e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.013835077897515968e18, 18, "Lending rate");

        (,, positionId) = env.createInstrumentAndPositionId(env.token(DAI), env.token(WETH), mm);
        (borrowingRate, lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.02293576779769621e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.05e18, 18, "Lending rate");
    }

    function testRewards_NoPosition() public {
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), address(wstEth), "Lend reward[0] token");
        assertEq(lending[0].token.name, "Wrapped liquid staked Ether 2.0", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "wstETH", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.001196575179716341e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1156.4077068e18, 18, "Lend reward[0] usdPrice");
    }

    function testRewards_ForPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(3 days);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), address(wstEth), "Lend reward[0] token");
        assertEq(lending[0].token.name, "Wrapped liquid staked Ether 2.0", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "wstETH", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.001196389158181296e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0.000085045182783913e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1156.4077068e18, 18, "Lend reward[0] usdPrice");

        vm.prank(TRADER);
        contango.claimRewards(positionId, TRADER);

        skip(15 days);

        (, lending) = sut.rewards(positionId);
        assertEqDecimal(lending[0].claimable, 0.000017658687258605e18, lending[0].token.decimals, "Lend reward[0] claimable");
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

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../AbstractMMV.t.sol";

contract DolomiteMoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IDolomiteMargin internal dolomite;

    constructor() AbstractMarketViewTest(MM_DOLOMITE) { }

    function setUp() public {
        super.setUp(Network.Arbitrum, 204_827_569);
        dolomite = env.dolomite();
    }

    function _oraclePrecision(uint256 x) internal pure override returns (uint256) {
        return x * WAD;
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 228_414.545305e6, instrument.quoteDecimals, "Borrowing liquidity");

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 beforePosition) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 199_218.070933357702439974e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_DOLOMITE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.869565217391304347e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.869565217391304347e18, 18, "Liquidation threshold");
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

        assertEqDecimal(ltv, 0.869565217391304347e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.869565217391304347e18, 18, "Liquidation threshold");
    }

    function testThresholds_CollateralMarginPremium() public {
        instrument = env.createInstrument(env.erc20(LINK), env.erc20(USDC));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_DOLOMITE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.8e18, 18, "Liquidation threshold");
    }

    function testThresholds_DebtMarginPremium() public {
        instrument = env.createInstrument(env.erc20(USDC), env.erc20(PENDLE));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_DOLOMITE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.666666666666666666e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.666666666666666666e18, 18, "Liquidation threshold");
    }

    function testThresholds_CollateralAndDebtMarginPremium() public {
        instrument = env.createInstrument(env.erc20(LINK), env.erc20(PENDLE));
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_DOLOMITE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.613333333333333333e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.613333333333333333e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.170113441515979052e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.055655947217187262e18, 18, "Lending rate");
    }

    function testAvailableActions_isClosing() public {
        uint256 market = dolomite.getMarketIdByTokenAddress(instrument.quote);
        vm.mockCall(address(dolomite), abi.encodeWithSelector(dolomite.getMarketIsClosing.selector, market), abi.encode(true));

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testLimits() public override {
        vm.mockCall(address(dolomite), abi.encodeWithSelector(dolomite.getMinBorrowedValue.selector), abi.encode(100e36));

        Limits memory limits = sut.limits(positionId);

        assertEqDecimal(limits.minBorrowing, 100.0e6, instrument.quoteDecimals, "Min borrowing");
        assertEqDecimal(limits.maxBorrowing, type(uint256).max, instrument.quoteDecimals, "Max borrowing");
        assertEqDecimal(limits.minBorrowingForRewards, 0, instrument.quoteDecimals, "Min borrowing for rewards");
        assertEqDecimal(limits.minLending, 0, instrument.baseDecimals, "Min lending");
        assertEqDecimal(limits.maxLending, type(uint256).max, instrument.baseDecimals, "Max lending");
        assertEqDecimal(limits.minLendingForRewards, 0, instrument.baseDecimals, "Min lending for rewards");
    }

}

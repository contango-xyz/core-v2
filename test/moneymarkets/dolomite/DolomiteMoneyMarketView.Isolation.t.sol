//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../AbstractMMV.t.sol";

contract DolomiteMoneyMarketViewIsolationTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IDolomiteMargin internal dolomite;
    IERC20 internal isolationToken;

    constructor() AbstractMarketViewTest(MM_DOLOMITE) { }

    function setUp() public {
        baseUsdPrice = 970e8;
        quoteUsdPrice = 1000e8;
        oracleDecimals = 8;

        env = provider(Network.Arbitrum);
        env.init(203_041_671);

        contango = env.contango();
        sut = env.contangoLens().moneyMarketView(mm);

        instrument = env.createInstrument(env.erc20(PTweETH27JUN2024), env.erc20(WETH));

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: int256(baseUsdPrice),
            quoteUsdPrice: int256(quoteUsdPrice),
            uniswapFee: 500
        });

        Payload payload = Payload.wrap(bytes5(uint40(42)));
        positionId = encode(instrument.symbol, MM_DOLOMITE, PERP, 0, payload);

        dolomite = env.dolomite();

        isolationToken = IERC20(0x6Cc56e9cA71147D40b10a8cB8cBe911C1Faf4Cf8);
        vm.mockCall(
            0xBfca44aB734E57Dc823cA609a0714EeC9ED06cA0, abi.encodeWithSignature("getPrice(address)", isolationToken), abi.encode(970e18)
        );

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function _oraclePrecision(uint256 x) internal pure override returns (uint256) {
        return x * WAD;
    }

    function testBalances_ExistingPosition() public override {
        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 10e18, cashflow: 3 ether, cashflowCcy: Currency.Quote });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10e18, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6.7 ether, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalancesUSD() public override {
        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 10e18, cashflow: 3 ether, cashflowCcy: Currency.Quote });

        Balances memory balances = sut.balancesUSD(positionId);

        assertApproxEqRelDecimal(balances.collateral, 9700e18, TOLERANCE, 18, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6700e18, TOLERANCE, 18, "Debt balance");
    }

    function testBaseQuoteRate() public view override {
        assertEqDecimal(sut.baseQuoteRate(positionId), 0.97e18, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 0.97e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 1e18, 18, "Quote price in native token");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 366.21400339822201161 ether, instrument.quoteDecimals, "Borrowing liquidity");

        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 10e18, cashflow: 3 ether, cashflowCcy: Currency.Quote });

        (uint256 afterPosition,) = sut.liquidity(positionId);
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6.7 ether, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testLendingLiquidity() public view {
        (, uint256 beforePosition) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 416.614129467615064145e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.833333333333333333e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.833333333333333333e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 10e18, cashflow: 3 ether, cashflowCcy: Currency.Quote });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.833333333333333333e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.833333333333333333e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.149906267980675407e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0, 18, "Lending rate");
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

        assertEqDecimal(limits.minBorrowing, 0.1 ether, instrument.quoteDecimals, "Min borrowing");
        assertEqDecimal(limits.maxBorrowing, type(uint256).max, instrument.quoteDecimals, "Max borrowing");
        assertEqDecimal(limits.minBorrowingForRewards, 0, instrument.quoteDecimals, "Min borrowing for rewards");
        assertEqDecimal(limits.minLending, 0, instrument.baseDecimals, "Min lending");
        assertEqDecimal(limits.maxLending, type(uint256).max, instrument.baseDecimals, "Max lending");
        assertEqDecimal(limits.minLendingForRewards, 0, instrument.baseDecimals, "Min lending for rewards");
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IPoolConfiguratorV2.sol";

import "../AbstractMMV.t.sol";

contract AaveV2MoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IPool internal pool;
    IPoolConfiguratorV2 internal poolConfigurator;

    constructor() AbstractMarketViewTest(MM_AAVE_V2) { }

    function setUp() public {
        super.setUp(Network.Mainnet);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfiguratorV2(IPoolAddressesProviderV2(address(env.aaveV2AddressProvider())).getLendingPoolConfigurator());

        vm.mockCall(address(env.aaveV2AddressProvider()), abi.encodeWithSignature("getPoolAdmin()"), abi.encode(address(this)));
        vm.mockCall(address(env.aaveV2AddressProvider()), abi.encodeWithSignature("getEmergencyAdmin()"), abi.encode(address(this)));

        stubChainlinkPrice(0.001e18, CHAINLINK_USDC_ETH);
    }

    function testPrices() public view override {
        Prices memory prices = sut.prices(positionId);

        // V2 common ccy is ETH
        assertEqDecimal(prices.collateral, 1e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
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

        assertEqDecimal(beforePosition, 46_382_845.60563e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 3_261_199.605417499593638528e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
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
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.040225334016594398e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.012761643445808913e18, 18, "Lending rate");
    }

    function testAvailableActions_BaseFrozen() public {
        poolConfigurator.freezeReserve(instrument.base);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteFrozen() public {
        poolConfigurator.freezeReserve(instrument.quote);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BothFrozen() public {
        poolConfigurator.freezeReserve(instrument.base);
        poolConfigurator.freezeReserve(instrument.quote);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_PoolPaused() public {
        poolConfigurator.setPoolPause(true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertEq(availableActions.length, 0, "No available actions");
    }

    function testAvailableActions_BaseCollateralDisabled() public {
        (,, positionId) = env.createInstrumentAndPositionId(IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0), env.token(USDC), mm);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteBorrowingDisabled() public {
        poolConfigurator.disableBorrowingOnReserve(instrument.quote);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

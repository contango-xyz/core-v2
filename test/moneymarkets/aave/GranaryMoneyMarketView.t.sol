//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./IPoolConfiguratorV2.sol";

import "../AbstractMMV.t.sol";

contract GranaryMoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IPool internal pool;
    IPoolConfiguratorV2 internal poolConfigurator;

    address internal rewardsToken = 0xfD389Dc9533717239856190F42475d3f263a270d;

    constructor() AbstractMarketViewTest(MM_GRANARY) { }

    function setUp() public {
        super.setUp(Network.Optimism, 112_831_424);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfiguratorV2(env.granaryAddressProvider().getLendingPoolConfigurator());

        vm.mockCall(address(env.granaryAddressProvider()), abi.encodeWithSignature("getPoolAdmin()"), abi.encode(address(this)));
        vm.mockCall(address(env.granaryAddressProvider()), abi.encodeWithSignature("getEmergencyAdmin()"), abi.encode(address(this)));
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

        assertEqDecimal(beforePosition, 113_294.674626e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 45_002.345636789151075274e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
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

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.85e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.241227720739151775e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.012128647204727021e18, 18, "Lending rate");
    }

    function testRewards_NoPosition() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 2057e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Granary Token", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "GRAIN", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.121154227159298165e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.011639476582009562e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Granary Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "GRAIN", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.003256289253431882e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.011639476582009562e18, 18, "Lend reward[0] usdPrice");
    }

    function testRewards_ForPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 minutes);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Granary Token", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "GRAIN", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.058339400305679442e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.117893560655856332e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.005658471843466e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Granary Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "GRAIN", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.003237233014526804e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0.01088488160848875e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.005658471843466e18, 18, "Lend reward[0] usdPrice");

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
        (,, positionId) = env.createInstrumentAndPositionId(IERC20(0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921), env.token(USDC), mm);

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

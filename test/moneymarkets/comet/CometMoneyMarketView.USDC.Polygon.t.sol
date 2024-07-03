//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../AbstractMMV.t.sol";

contract CometMoneyMarketViewPolygonTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IComet internal comet;
    CometReverseLookup internal reverseLookup;
    address internal rewardsToken;

    constructor() AbstractMarketViewTest(MM_COMET) { }

    function setUp() public {
        super.setUp(Network.Polygon, 55_625_206);

        comet = env.comet();
        reverseLookup = CometMoneyMarketView(address(sut)).reverseLookup();
        rewardsToken = 0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c;
        positionId = encode(instrument.symbol, mm, PERP, 0, Payload.wrap(bytes5(uint40(1))));

        env.spotStub().stubPrice({
            base: env.erc20(WETH),
            quote: env.erc20(WMATIC),
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 0.9e8,
            uniswapFee: 500
        });
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1111.111111111111111111e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 1.111111111111111111e18, 18, "Quote price in native token");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 2_124_325.429515e6, instrument.quoteDecimals, "Borrowing liquidity");

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 18_576.967475645675071078e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.775e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testThresholds_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.775e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.114813717416474287e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0, 18, "Lending rate");
    }

    function testRewards_WETHUSDC() public {
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "(PoS) Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.009639954889703594e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 75.786451e18, 18, "Borrow reward[0] usdPrice");
    }

    function testRewards_ForPosition_UnderMin() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 0, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "(PoS) Compound", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "COMP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.009593754249304849e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.031407e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 75.786451e18, 18, "Borrow reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient), borrowing[0].claimable, IERC20(rewardsToken).decimals(), "Claimed rewards"
        );
    }

    function testAvailableActions_SupplyPaused() public {
        vm.prank(comet.pauseGuardian());
        comet.pause({ supplyPaused: true, transferPaused: false, withdrawPaused: false, absorbPaused: false, buyPaused: false });

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_WithdrawPaused() public {
        vm.prank(comet.pauseGuardian());
        comet.pause({ supplyPaused: false, transferPaused: false, withdrawPaused: true, absorbPaused: false, buyPaused: false });

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BothPaused() public {
        vm.prank(comet.pauseGuardian());
        comet.pause({ supplyPaused: true, transferPaused: false, withdrawPaused: true, absorbPaused: false, buyPaused: false });

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testLimits() public view override {
        Limits memory limits = sut.limits(positionId);

        assertEqDecimal(limits.minBorrowing, 100.0e6, instrument.quoteDecimals, "Min borrowing");
        assertEqDecimal(limits.maxBorrowing, type(uint256).max, instrument.quoteDecimals, "Max borrowing");
        assertEqDecimal(limits.minBorrowingForRewards, 1_000_000.0e6, instrument.quoteDecimals, "Min borrowing for rewards");
        assertEqDecimal(limits.minLending, 0, instrument.baseDecimals, "Min lending");
        assertEqDecimal(limits.maxLending, type(uint256).max, instrument.baseDecimals, "Max lending");
        assertEqDecimal(limits.minLendingForRewards, 0, instrument.baseDecimals, "Min lending for rewards");
    }

    function testIrmRaw() public view {
        CometMoneyMarketView.IRMData memory irmData = abi.decode(sut.irmRaw(positionId), (CometMoneyMarketView.IRMData));

        assertEq(irmData.totalSupply, comet.totalSupply(), "Total supply");
        assertEq(irmData.totalBorrow, comet.totalBorrow(), "Total borrow");
        assertEq(irmData.borrowKink, comet.borrowKink(), "Borrow kink");
        assertEq(
            irmData.borrowPerSecondInterestRateSlopeLow,
            comet.borrowPerSecondInterestRateSlopeLow(),
            "Borrow per second interest rate slope low"
        );
        assertEq(
            irmData.borrowPerSecondInterestRateSlopeHigh,
            comet.borrowPerSecondInterestRateSlopeHigh(),
            "Borrow per second interest rate slope high"
        );
        assertEq(irmData.borrowPerSecondInterestRateBase, comet.borrowPerSecondInterestRateBase(), "Borrow per second interest rate base");
    }

}

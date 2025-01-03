//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../AbstractMMV.t.sol";

contract EulerMoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IEulerVault public constant ethVault = IEulerVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2);
    IEulerVault public constant usdcVault = IEulerVault(0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9);
    // IERC20 public constant rewardToken = IERC20(0xf23a2a96C4EE7322E7b6a2EbB914c789a43eF39E);

    uint16 ethId;
    uint16 usdcId;

    constructor() AbstractMarketViewTest(MM_EULER) { }

    function setUp() public {
        super.setUp(Network.Mainnet, 20_678_328, WETH, 1000e8, USDC, 1e8, 18);

        EulerMoneyMarketView mmv = EulerMoneyMarketView(address(sut));

        vm.startPrank(TIMELOCK_ADDRESS);
        // mmv.rewardOperator().addLiveReward(ethVault, rewardToken);

        ethId = mmv.reverseLookup().setVault(ethVault);
        usdcId = mmv.reverseLookup().setVault(usdcVault);
        vm.stopPrank();

        positionId = encode(Symbol.wrap("WETHUSDC"), MM_EULER, PERP, 0, baseQuotePayload(ethId, usdcId));
    }

    function testPriceInNativeToken() public view {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 0, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0, 18, "Quote price in native token");
    }

    function testBalancesUSD() public override {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: _basePrecision(_baseTestQty()),
            cashflow: int256(_quotePrecision(_quoteTestQty())),
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balancesUSD(positionId);

        assertApproxEqRelDecimal(balances.collateral, 0, 0, 18, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 0, 0, 18, "Debt balance");
    }

    function testPriceInUSD() public view override {
        assertApproxEqAbsDecimal(sut.priceInUSD(instrument.base), 0, 0, 18, "Base price in USD");
        assertApproxEqAbsDecimal(sut.priceInUSD(instrument.quote), 0, 0, 18, "Quote price in USD");
    }

    function testPrices_Escrow() public {
        vm.startPrank(TIMELOCK_ADDRESS);
        ethId = EulerMoneyMarketView(address(sut)).reverseLookup().setVault(IEulerVault(0xb3b36220fA7d12f7055dab5c9FD18E860e9a6bF8));
        vm.stopPrank();

        positionId = encode(Symbol.wrap("WETHUSDC"), MM_EULER, PERP, 0, baseQuotePayload(ethId, usdcId));

        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, 18, "Debt price");
        assertEq(prices.unit, 10 ** 18, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 2_147_116.73383e6, instrument.quoteDecimals, "Borrowing liquidity");

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
        (, uint256 lending) = sut.liquidity(positionId);
        assertEqDecimal(lending, 2_890_608.174084527639796044e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.79e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.81e18, 18, "Liquidation threshold");
    }

}

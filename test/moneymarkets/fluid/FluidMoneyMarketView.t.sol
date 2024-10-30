//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../AbstractMMV.t.sol";

contract FluidMoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    constructor() AbstractMarketViewTest(MM_FLUID) { }

    function setUp() public {
        super.setUp(Network.Mainnet, 20_714_976, WETH, 1000e8, USDC, 1e8, 6);

        stubChainlinkPrice(0.001e18, CHAINLINK_USDC_ETH);

        positionId = encode(Symbol.wrap("WETHUSDC"), MM_FLUID, PERP, 0, Payload.wrap(bytes5(uint40(11))));
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);
        assertEqDecimal(beforePosition, 2_473_754.847288e6, instrument.quoteDecimals, "Borrowing liquidity");

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
        assertEqDecimal(lending, 2_908_354.102848332806698574e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.87e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.92e18, 18, "Liquidation threshold");
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

}

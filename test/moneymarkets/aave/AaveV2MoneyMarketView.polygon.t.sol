//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../AbstractMMV.t.sol";

contract AaveV2MoneyMarketViewTest is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;

    IPool internal pool;

    constructor() AbstractMarketViewTest(MM_AAVE_V2) { }

    function setUp() public {
        super.setUp(Network.Polygon);

        pool = AaveMoneyMarketView(address(sut)).pool();

        // USDC / ETH - 18 decimals
        env.spotStub().stubChainlinkPrice(0.001e18, 0xefb7e6be8356cCc6827799B6A7348eE674A80EaE);
        // MATIC / ETH - 18 decimals
        env.spotStub().stubChainlinkPrice(0.002e18, 0x327e23A4855b6F663a28c5161541d69Af8973302);
        env.spotStub().stubChainlinkPrice(2e8, address(env.erc20(WMATIC).chainlinkUsdOracle));
    }

    function testPrices() public view override {
        Prices memory prices = sut.prices(positionId);

        // V2 common ccy is ETH
        assertEqDecimal(prices.collateral, 1e18, 18, "Collateral price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testPriceInNativeToken() public view {
        // MATIC / USD = 2, so 1 ETH = 500 MATIC
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 500e18, 18, "Base price in native token");
        // MATIC / USD = 2, so 1 USDC = 0.5 MATIC
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.5e18, 18, "Quote price in native token");
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

        assertEqDecimal(beforePosition, 10_531_495.462401e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 208_987.425239629259759118e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
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
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.031930887276478957e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.000628396649997339e18, 18, "Lending rate");
    }

}

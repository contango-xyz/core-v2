//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract SonneMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    SonneMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_SONNE;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init(110_502_427);

        contango = env.contango();

        sut = new SonneMoneyMarketView(MM_SONNE, contango.positionFactory(), env.compoundComptroller(), env.nativeToken());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });
    }

    function testBalances_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SONNE, PERP, 0);

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId, instrument.base, instrument.quote);

        assertEqDecimal(prices.collateral, 1000e18, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(beforePosition, 2_623_450.499473e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e6 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(liquidity, 51_435.3140536652894657e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_SONNE, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.75e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.75e18, 18, "Liquidation threshold");
    }

    function testThresholds_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.75e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.75e18, 18, "Liquidation threshold");
    }

    // function testRates() public {
    //     (uint256 borrowingRate, uint256 lendingRate) = sut.rates(instrument.base, instrument.quote);

    //     assertEqDecimal(borrowingRate, 0.043541006683424253e18, 18, "Borrowing rate");
    //     assertEqDecimal(lendingRate, 0, 18, "Lending rate");
    // }

}

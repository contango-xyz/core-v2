//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract CompoundMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    CompoundMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_COMPOUND;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_233_968);

        contango = env.contango();

        sut = new CompoundMoneyMarketView(MM_COMPOUND, contango.positionFactory(), env.compoundComptroller(), env.nativeToken());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        address oracle = env.compoundComptroller().oracle();
        vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "ETH"), abi.encode(1000e6));
        vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "USDC"), abi.encode(1e6));
    }

    function testBalances_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_COMPOUND, PERP, 0);

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

        assertEqDecimal(prices.collateral, 1000e6, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e6, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e6, "Oracle Unit");
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

        assertEqDecimal(beforePosition, 62_407_292.124462e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e6 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(liquidity, 3_106_779.195479997902026967e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_COMPOUND, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
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

        assertEqDecimal(ltv, 0.825e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.825e18, 18, "Liquidation threshold");
    }

    // function testRates() public {
    //     (uint256 borrowingRate, uint256 lendingRate) = sut.rates(instrument.base, instrument.quote);

    //     assertEqDecimal(borrowingRate, 0.043541006683424253e18, 18, "Borrowing rate");
    //     assertEqDecimal(lendingRate, 0, 18, "Lending rate");
    // }

}

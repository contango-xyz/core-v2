//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract ExactlyMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_EXACTLY;

    IERC20 internal op = IERC20(0x4200000000000000000000000000000000000042);
    IERC20 internal exa = IERC20(0x1e925De1c68ef83bD98eE3E130eF14a50309C01B);

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init(110_502_427);

        contango = env.contango();

        sut = env.contangoLens().moneyMarketView(mm);

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, MM_EXACTLY, PERP, 0);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
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

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1000e18, instrument.baseDecimals, "Collateral price");
        assertEqDecimal(prices.debt, 1e18, instrument.quoteDecimals, "Debt price");
        assertEq(prices.unit, 1e18, "Oracle Unit");
    }

    function testBaseQuoteRate() public {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(baseQuoteRate, 1000e6, instrument.quoteDecimals, "Base quote rate");
    }

    function testPriceInNativeToken() public {
        assertEqDecimal(sut.priceInNativeToken(instrument.base), 1e18, 18, "Base price in native token");
        assertEqDecimal(sut.priceInNativeToken(instrument.quote), 0.001e18, 18, "Quote price in native token");
    }

    function testPriceInUSD() public {
        assertEqDecimal(sut.priceInUSD(instrument.base), 1000e18, 18, "Base price in USD");
        assertEqDecimal(sut.priceInUSD(instrument.quote), 1e18, 18, "Quote price in USD");
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

        assertEqDecimal(beforePosition, 1_065_369.591346e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 51_435.3140536652894657e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_EXACTLY, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.7826e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.7826e18, 18, "Liquidation threshold");
    }

    function testThresholds_ValidPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.7826e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.7826e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.043541006683424253e18, 18, "Borrowing rate");
        // Lending rate is calculated off-chain for Exactly
        assertEqDecimal(lendingRate, 0, 18, "Lending rate");
    }

    function testRewards_NoPosition() public {
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 2, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), address(op), "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Optimism", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "OP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.03697744784152548e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1.2986e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(borrowing[1].token.token), address(exa), "Borrow reward[1] token");
        assertEq(borrowing[1].token.name, "exactly", "Borrow reward[1] name");
        assertEq(borrowing[1].token.symbol, "EXA", "Borrow reward[1] symbol");
        assertEq(borrowing[1].token.decimals, 18, "Borrow reward[1] decimals");
        assertEq(borrowing[1].token.unit, 1e18, "Borrow reward[1] unit");
        assertEqDecimal(borrowing[1].rate, 0, borrowing[1].token.decimals, "Borrow reward[1] rate");
        assertEqDecimal(borrowing[1].claimable, 0, borrowing[1].token.decimals, "Borrow reward[1] claimable");
        assertEqDecimal(borrowing[1].usdPrice, 0.88431652e18, 18, "Borrow reward[1] usdPrice");

        assertEq(address(lending[0].token.token), address(op), "Lend reward[0] token");
        assertEq(lending[0].token.name, "Optimism", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "OP", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.01263594343058604e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1.2986e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), address(exa), "Lend reward[1] token");
        assertEq(lending[1].token.name, "exactly", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "EXA", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.00000230529059652e18, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.88431652e18, 18, "Lend reward[1] usdPrice");
    }

    function testRewards_ForPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 2, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), address(op), "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Optimism", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "OP", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 8.80952576953623012e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 7.751756135264213528e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1.2986e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(borrowing[1].token.token), address(exa), "Borrow reward[1] token");
        assertEq(borrowing[1].token.name, "exactly", "Borrow reward[1] name");
        assertEq(borrowing[1].token.symbol, "EXA", "Borrow reward[1] symbol");
        assertEq(borrowing[1].token.decimals, 18, "Borrow reward[1] decimals");
        assertEq(borrowing[1].token.unit, 1e18, "Borrow reward[1] unit");
        assertEqDecimal(borrowing[1].rate, 0, borrowing[1].token.decimals, "Borrow reward[1] rate");
        assertEqDecimal(borrowing[1].claimable, 0, borrowing[1].token.decimals, "Borrow reward[1] claimable");
        assertEqDecimal(borrowing[1].usdPrice, 0.88431652e18, 18, "Borrow reward[1] usdPrice");

        assertEq(address(lending[0].token.token), address(op), "Lend reward[0] token");
        assertEq(lending[0].token.name, "Optimism", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "OP", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 3.01717492285583352e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 1.596910666741632862e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1.2986e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), address(exa), "Lend reward[1] token");
        assertEq(lending[1].token.name, "exactly", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "EXA", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.00000229965454392e18, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0.000602332070501988e18, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.88431652e18, 18, "Lend reward[1] usdPrice");
    }

}

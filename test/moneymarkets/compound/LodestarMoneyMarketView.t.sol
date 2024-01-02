//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract LodestarMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_LODESTAR;

    address internal rewardsToken;
    address internal arbToken;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.01e18;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(152_284_580);

        contango = env.contango();

        sut = env.contangoLens().moneyMarketView(mm);
        rewardsToken = address(env.compoundComptroller().getCompAddress());
        arbToken = address(LodestarMoneyMarketView(address(sut)).arbToken());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
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

        // Lodestar oracle is ETH based
        assertEqDecimal(prices.collateral, 1e18, 18, "ETH price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "USDC price");
        assertEq(prices.unit, 1e18, "Oracle Unit");

        (,, positionId) = env.createInstrumentAndPositionId(env.token(ARB), env.token(DAI), mm);
        env.spotStub().stubPrice({ base: env.erc20(ARB), quote: env.erc20(DAI), baseUsdPrice: 1.2e8, quoteUsdPrice: 1e8, uniswapFee: 500 });
        prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 0.0012e18, 18, "ARB price");
        assertEqDecimal(prices.debt, 0.001e18, 18, "DAI price");
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

        assertEqDecimal(beforePosition, 1_236_015.537889e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(
            beforePosition - afterPosition, 6000e6 * 0.95e18 / 1e18, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta"
        );
    }

    function testBorrowingLiquidity_ETH() public {
        instrument = env.createInstrument(env.erc20(USDC), env.erc20(WETH));
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        (uint256 liq,) = sut.liquidity(positionId);

        assertEqDecimal(liq, 273.333542437074556297e18, instrument.baseDecimals, "Borrowing liquidity");
    }

    function testLendingLiquidity_LiquidityIsZeroWhenSupplyIsGreaterThanCap() public {
        // wstETH
        (,, positionId) = env.createInstrumentAndPositionId(IERC20(0x5979D7b546E38E414F7E9822514be443A4800529), instrument.base, mm);
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 0, instrument.baseDecimals, "Lending liquidity");
    }

    function testLendingLiquidity() public {
        (, uint256 liquidity) = sut.liquidity(positionId);

        assertEqDecimal(liquidity, 119.827487683329791758e18, instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.8e18, 18, "Liquidation threshold");
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

        assertEqDecimal(ltv, 0.8e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.8e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.148687295031015408e18, 18, "Borrowing rate");
        assertEqDecimal(lendingRate, 0.047431085060641444e18, 18, "Lending rate");
    }

    function testRewards_WETHUSDC() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1974e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 2, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), arbToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Arbitrum", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "ARB", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.037976294322526892e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1.0519e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), arbToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Arbitrum", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "ARB", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.037976294322526892e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1.0519e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(borrowing[1].token.token), rewardsToken, "Borrow reward[1] token");
        assertEq(borrowing[1].token.name, "Lodestar", "Borrow reward[1] name");
        assertEq(borrowing[1].token.symbol, "LODE", "Borrow reward[1] symbol");
        assertEq(borrowing[1].token.decimals, 18, "Borrow reward[1] decimals");
        assertEq(borrowing[1].token.unit, 1e18, "Borrow reward[1] unit");
        assertEqDecimal(borrowing[1].rate, 0.006848705579441079e18, borrowing[1].token.decimals, "Borrow reward[1] rate");
        assertEqDecimal(borrowing[1].claimable, 0, borrowing[1].token.decimals, "Borrow reward[1] claimable");
        assertEqDecimal(borrowing[1].usdPrice, 0.370218198876054396e18, 18, "Borrow reward[1] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken, "Lend reward[1] token");
        assertEq(lending[1].token.name, "Lodestar", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "LODE", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.00857090358149852e18, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.370218198876054396e18, 18, "Lend reward[1] usdPrice");
    }

    function testRewards_USDCWETH() public {
        // Set the price for the block I was comparing with so the values more or less match
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1974e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (,, positionId) = env.createInstrumentAndPositionId(instrument.quote, instrument.base, mm);
        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 2, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), arbToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Arbitrum", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "ARB", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.037976294322526892e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1.0519e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), arbToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Arbitrum", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "ARB", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.037976294322526892e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1.0519e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(borrowing[1].token.token), rewardsToken, "Borrow reward[1] token");
        assertEq(borrowing[1].token.name, "Lodestar", "Borrow reward[1] name");
        assertEq(borrowing[1].token.symbol, "LODE", "Borrow reward[1] symbol");
        assertEq(borrowing[1].token.decimals, 18, "Borrow reward[1] decimals");
        assertEq(borrowing[1].token.unit, 1e18, "Borrow reward[1] unit");
        assertEqDecimal(borrowing[1].rate, 0.010392605517013153e18, borrowing[1].token.decimals, "Borrow reward[1] rate");
        assertEqDecimal(borrowing[1].claimable, 0, borrowing[1].token.decimals, "Borrow reward[1] claimable");
        assertEqDecimal(borrowing[1].usdPrice, 0.370218198876054396e18, 18, "Borrow reward[1] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken, "Lend reward[1] token");
        assertEq(lending[1].token.name, "Lodestar", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "LODE", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.005604377276778105e18, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 0, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.370218198876054396e18, 18, "Lend reward[1] usdPrice");
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
        vm.roll(block.number + 15 * 24 * 60 * 60 / 12);

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(15 days);
        vm.roll(block.number + 15 * 24 * 60 * 60 / 12);

        // Simulate an airdrop of 10 ARB
        deal(arbToken, address(contango.positionFactory().moneyMarket(positionId)), 10e18);

        (Reward[] memory borrowing, Reward[] memory lending) = sut.rewards(positionId);

        assertEq(borrowing.length, 2, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), arbToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Arbitrum", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "ARB", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.044919095428106633e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 5e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 1.0519e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), arbToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Arbitrum", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "ARB", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.044919095428106633e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 5e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 1.0519e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(borrowing[1].token.token), rewardsToken, "Borrow reward[1] token");
        assertEq(borrowing[1].token.name, "Lodestar", "Borrow reward[1] name");
        assertEq(borrowing[1].token.symbol, "LODE", "Borrow reward[1] symbol");
        assertEq(borrowing[1].token.decimals, 18, "Borrow reward[1] decimals");
        assertEq(borrowing[1].token.unit, 1e18, "Borrow reward[1] unit");
        assertEqDecimal(borrowing[1].rate, 0.003441870289245172e18, borrowing[1].token.decimals, "Borrow reward[1] rate");
        assertEqDecimal(borrowing[1].claimable, 20.744542337493439346e18, borrowing[1].token.decimals, "Borrow reward[1] claimable");
        assertEqDecimal(borrowing[1].usdPrice, 0.187547213209754e18, 18, "Borrow reward[1] usdPrice");

        assertEq(address(lending[1].token.token), rewardsToken, "Lend reward[1] token");
        assertEq(lending[1].token.name, "Lodestar", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "LODE", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0.008518307626210048e18, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 49.019437217579071235e18, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 0.187547213209754e18, 18, "Lend reward[1] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(TRADER);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(arbToken).balanceOf(recipient),
            borrowing[0].claimable + lending[0].claimable,
            IERC20(arbToken).decimals(),
            "Claimed ARB rewards"
        );
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient),
            borrowing[1].claimable + lending[1].claimable,
            IERC20(rewardsToken).decimals(),
            "Claimed LODE rewards"
        );
    }

}

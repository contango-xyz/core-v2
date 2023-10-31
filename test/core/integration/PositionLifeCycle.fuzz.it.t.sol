//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

contract PositionLifeCycleIntegration is BaseTest {

    using Math for *;
    using SafeCast for *;
    using SignedMath for *;

    struct Booleans {
        bool cashflowInQuote;
        bool usePermit;
        bool dustBase;
        bool dustQuote;
    }

    uint256 private constant TOLERANCE = 0.00005e18;
    uint256 private constant LEVERAGE_TOLERANCE = 0.01e18;
    uint256 private constant LIQUIDITY_BUFFER = 0.05e18;

    int256 private constant MAX_PRICE_INCREASE = 1e18; // 100%
    int256 private constant MAX_PRICE_DECREASE = -0.4e18; // 40%

    Env internal env;
    TestInstrument internal instrument;

    MoneyMarketId mm;

    ERC20Data baseCcy;
    ERC20Data quoteCcy;

    Currency cashflowCcy;

    // function testFuzzFixed() public {
    //     // testFuzzCreatePosition();
    //     // testFuzzIncreasePosition();
    //     // testFuzzDecreasePosition();
    //     // testFuzzClosePosition();
    // }

    function testFuzzCreatePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 leverage,
        Booleans memory b
    ) public fuzzTestsEnabled {
        (env, mm, baseCcy, quoteCcy) = _boundParams(networkId, mmId, baseId, quoteId);
        env.init();
        cashflowCcy = b.cashflowInQuote ? Currency.Quote : Currency.Base;
        {
            ERC20Data memory cashflowERC20 = b.cashflowInQuote ? quoteCcy : baseCcy;
            env.positionActions().setUsePermit(b.usePermit && cashflowERC20.hasPermit);

            if (b.dustBase) deal(address(baseCcy.token), address(env.contango()), 1);
            if (b.dustQuote) deal(address(quoteCcy.token), address(env.contango()), 1);
        }

        quantity = bound(quantity, env.bounds(baseCcy.symbol).min, env.bounds(baseCcy.symbol).max);
        leverage = _boundLeverage(leverage);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        env.positionActions().setSlippageTolerance(0.005e4);
        env.tsQuoter().setLiquidityBuffer(TSQuoter.LiquidityBuffer({ lending: LIQUIDITY_BUFFER, borrowing: LIQUIDITY_BUFFER }));
        _stubUniswapInfiniteLiquidity();

        (TSQuote memory quote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);

        assertApproxEqRelDecimal(trade.quantity, quote.quantity, TOLERANCE, instrument.baseDecimals, "trade.quantity");

        IMoneyMarketView mmv = env.tsQuoter().moneyMarkets(mm);
        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);
        assertApproxEqRelDecimal(balances.collateral, quote.quantity.toUint256(), TOLERANCE, instrument.baseDecimals, "variable collateral");
        assertApproxEqRelDecimal(
            balances.debt,
            uint256(int256(quote.execParams.swapAmount) - (cashflowCcy == Currency.Quote ? quote.cashflowUsed : int256(0)))
                + quote.transactionFees,
            TOLERANCE,
            instrument.quoteDecimals,
            "variable debt"
        );
        _assertLeverage(mmv, positionId, leverage);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
        _assertCashflowInvariants(quote);
    }

    function testFuzzIncreasePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 increaseQuantity,
        uint256 leverage,
        int256 marketMovement,
        Booleans memory b
    ) public fuzzTestsEnabled {
        (env, mm, baseCcy, quoteCcy) = _boundParams(networkId, mmId, baseId, quoteId);
        env.init();
        {
            ERC20Data memory cashflowERC20 = b.cashflowInQuote ? quoteCcy : baseCcy;
            env.positionActions().setUsePermit(b.usePermit && cashflowERC20.hasPermit);

            if (b.dustBase) deal(address(baseCcy.token), address(env.contango()), 1);
            if (b.dustQuote) deal(address(quoteCcy.token), address(env.contango()), 1);
        }
        cashflowCcy = b.cashflowInQuote ? Currency.Quote : Currency.Base;

        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });
        (, uint256 lendingLiquidity) = env.tsQuoter().moneyMarkets(mm).liquidity(
            env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0), baseCcy.token, quoteCcy.token
        );
        quantity = bound(quantity, env.bounds(baseCcy.symbol).min, lendingLiquidity / 2);
        uint256 openLeverage = _boundLeverage(leverage);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, openLeverage, toString(cashflowCcy));

        env.positionActions().setSlippageTolerance(0.01e4);
        env.tsQuoter().setLiquidityBuffer(TSQuoter.LiquidityBuffer({ lending: LIQUIDITY_BUFFER, borrowing: LIQUIDITY_BUFFER }));
        _stubUniswapInfiniteLiquidity();

        (TSQuote memory openQuote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, openLeverage, cashflowCcy);

        IMoneyMarketView mmv = env.tsQuoter().moneyMarkets(mm);
        uint256 actualOpenLeverage = _assertLeverage(mmv, positionId, openLeverage);

        skip(1 days);
        _movePrice(positionId, mmv, marketMovement);

        increaseQuantity = bound(increaseQuantity, env.bounds(baseCcy.symbol).min, env.bounds(baseCcy.symbol).max);
        uint256 increaseLeverage = _boundLeverage(openLeverage * 10);
        console.log("increase quantity %s, leverage %s, cashflowCcy %s", increaseQuantity, increaseLeverage, toString(cashflowCcy));

        TSQuote memory increaseQuote;
        (increaseQuote, positionId, trade) = env.positionActions().openPosition(positionId, increaseQuantity, increaseLeverage, cashflowCcy);

        // compensate for fees when trading at the liquidity limit
        uint256 extraTolerance = 0.001e18;
        int256 quantityAdjustment = _quantityAdjustmentOnIncrease(actualOpenLeverage, increaseLeverage, increaseQuote, trade);

        assertApproxEqRelDecimal(
            trade.quantity,
            increaseQuote.quantity + quantityAdjustment,
            TOLERANCE + extraTolerance,
            instrument.baseDecimals,
            "trade.quantity"
        );

        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);
        assertApproxEqRelDecimal(
            balances.collateral,
            (openQuote.quantity + increaseQuote.quantity).toUint256(),
            TOLERANCE * 2 + extraTolerance + 0.0001e18, // +0.01% for the interest accrual
            instrument.baseDecimals,
            "variable collateral"
        );
        _assertLeverage(mmv, positionId, increaseLeverage);

        env.checkInvariants(instrument, positionId, openQuote.execParams.flashLoanProvider);
        env.checkInvariants(instrument, positionId, increaseQuote.execParams.flashLoanProvider);
        _assertCashflowInvariants(increaseQuote);
    }

    function testFuzzDecreasePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 decreaseQuantity,
        uint256 leverage,
        int256 marketMovement,
        Booleans memory b
    ) public fuzzTestsEnabled {
        (env, mm, baseCcy, quoteCcy) = _boundParams(networkId, mmId, baseId, quoteId);
        env.init();
        {
            ERC20Data memory cashflowERC20 = b.cashflowInQuote ? quoteCcy : baseCcy;
            env.positionActions().setUsePermit(b.usePermit && cashflowERC20.hasPermit);

            if (b.dustBase) deal(address(baseCcy.token), address(env.contango()), 1);
            if (b.dustQuote) deal(address(quoteCcy.token), address(env.contango()), 1);
        }
        cashflowCcy = b.cashflowInQuote ? Currency.Quote : Currency.Base;

        quantity = bound(quantity, env.bounds(baseCcy.symbol).min, env.bounds(baseCcy.symbol).max);
        leverage = _boundLeverage(leverage);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        env.positionActions().setSlippageTolerance(0.01e4);
        env.tsQuoter().setLiquidityBuffer(TSQuoter.LiquidityBuffer({ lending: LIQUIDITY_BUFFER, borrowing: LIQUIDITY_BUFFER }));
        _stubUniswapInfiniteLiquidity();

        (TSQuote memory openQuote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);

        IMoneyMarketView mmv = env.tsQuoter().moneyMarkets(mm);
        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);
        _assertLeverage(mmv, positionId, leverage);

        skip(1 days);
        _movePrice(positionId, mmv, marketMovement);

        decreaseQuantity = bound(decreaseQuantity, env.bounds(baseCcy.symbol).min / 50, balances.collateral - balances.collateral / 10);
        vm.assume(decreaseQuantity < quantity);
        balances = mmv.balances(positionId, instrument.base, instrument.quote);

        leverage = _boundLeverage(leverage * 10);
        console.log("decrease quantity %s, leverage %s, cashflowCcy %s", decreaseQuantity, leverage, toString(cashflowCcy));

        TSQuote memory decreaseQuote;
        (decreaseQuote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: decreaseQuantity,
            leverage: leverage,
            cashflowCcy: cashflowCcy
        });
        uint256 totalQty = balances.collateral - decreaseQuote.quantity.abs();

        assertApproxEqRelDecimal(trade.quantity, decreaseQuote.quantity, TOLERANCE, instrument.baseDecimals, "trade.quantity");

        balances = mmv.balances(positionId, instrument.base, instrument.quote);
        if (balances.collateral > 0) {
            assertApproxEqRelDecimal(balances.collateral, totalQty, TOLERANCE, instrument.baseDecimals, "variable collateral");
            _assertLeverage(mmv, positionId, leverage);
        } else {
            assertApproxEqAbsDecimal(totalQty, 0, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, "closing qty");
        }

        uint256 contangoBaseTolerance = trade.quantity.abs().mulDiv(TOLERANCE, WAD); // % of traded quantity allowed for dust
        env.checkInvariants(instrument, positionId, openQuote.execParams.flashLoanProvider, contangoBaseTolerance);
        env.checkInvariants(instrument, positionId, decreaseQuote.execParams.flashLoanProvider, contangoBaseTolerance);
        _assertCashflowInvariants(decreaseQuote);
    }

    function testFuzzClosePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 leverage,
        int256 marketMovement,
        Booleans memory b
    ) public fuzzTestsEnabled {
        (env, mm, baseCcy, quoteCcy) = _boundParams(networkId, mmId, baseId, quoteId);
        env.init();
        {
            ERC20Data memory cashflowERC20 = b.cashflowInQuote ? quoteCcy : baseCcy;
            env.positionActions().setUsePermit(b.usePermit && cashflowERC20.hasPermit);

            if (b.dustBase) deal(address(baseCcy.token), address(env.contango()), 1);
            if (b.dustQuote) deal(address(quoteCcy.token), address(env.contango()), 1);
        }
        cashflowCcy = b.cashflowInQuote ? Currency.Quote : Currency.Base;

        quantity = bound(quantity, env.bounds(baseCcy.symbol).min, env.bounds(baseCcy.symbol).max);
        leverage = _boundLeverage(leverage);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        env.positionActions().setSlippageTolerance(0.005e4);
        env.tsQuoter().setLiquidityBuffer(TSQuoter.LiquidityBuffer({ lending: LIQUIDITY_BUFFER, borrowing: LIQUIDITY_BUFFER }));
        _stubUniswapInfiniteLiquidity();

        (TSQuote memory quote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);

        skip(1 days);

        IMoneyMarketView mmv = env.tsQuoter().moneyMarkets(mm);
        _movePrice(positionId, mmv, marketMovement);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: uint256(type(int256).max),
            cashflow: 0,
            cashflowCcy: cashflowCcy
        });

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");

        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);
        assertApproxEqAbsDecimal(balances.collateral, 0, env.bounds(baseCcy.symbol).dust, instrument.baseDecimals, "variable collateral");
        assertApproxEqAbsDecimal(balances.debt, 0, env.bounds(quoteCcy.symbol).dust, instrument.quoteDecimals, "variable debt");

        uint256 contangoBaseTolerance = trade.quantity.abs().mulDiv(TOLERANCE, WAD); // % of traded quantity allowed for dust
        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider, contangoBaseTolerance);
        if (cashflowCcy == Currency.Quote) {
            assertGt(instrument.quote.balanceOf(TRADER), 0, string.concat("trader quote (", instrument.quote.symbol(), ") withdraw"));
        } else {
            assertGt(instrument.base.balanceOf(TRADER), 0, string.concat("trader base (", instrument.base.symbol(), ") withdraw"));
        }
    }

    function _movePrice(PositionId positionId, IMoneyMarketView mmv, int256 marketMovement) private {
        // ensure any decrease in collateral will not put position into liquidation
        (uint256 ltv,) = mmv.thresholds(positionId, instrument.base, instrument.quote);
        Prices memory prices = mmv.prices(positionId, instrument.base, instrument.quote);
        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);

        int256 maxDecrease = MAX_PRICE_DECREASE;
        if (balances.debt > 0) {
            uint256 nCollateral = balances.collateral.mulDiv(prices.collateral, instrument.baseUnit);
            uint256 nDebt = balances.debt.mulDiv(prices.debt, instrument.quoteUnit);

            uint256 nMinCollateral = nDebt.mulDiv(WAD + WAD - ltv, WAD);
            maxDecrease = SignedMath.max(maxDecrease, -int256(WAD - nMinCollateral.mulDiv(WAD, nCollateral)));
        }

        env.spotStub().movePrice(instrument.baseData, int256(bound(marketMovement, maxDecrease, MAX_PRICE_INCREASE)));
    }

    function _stubUniswapInfiniteLiquidity() private {
        address poolAddress = env.spotStub().stubUniswapPrice({ base: baseCcy, quote: quoteCcy, spread: 0, uniswapFee: 500 });
        deal(address(baseCcy.token), poolAddress, type(uint160).max);
        deal(address(quoteCcy.token), poolAddress, type(uint160).max);
        deal(address(baseCcy.token), env.balancer(), type(uint256).max);
        deal(address(quoteCcy.token), env.balancer(), type(uint256).max);
    }

    function _boundParams(uint8 networkId, uint8 mmId, uint8 baseId, uint8 quoteId)
        private
        returns (Env env_, MoneyMarketId mm_, ERC20Data memory base_, ERC20Data memory quote_)
    {
        Network network = Network(bound(networkId, uint8(Network.Arbitrum), uint8(Network.Optimism)));
        env_ = provider(network);

        MoneyMarketId[] memory mms = env_.moneyMarkets();
        mm_ = mms[bound(mmId, 0, mms.length - 1)];

        ERC20Data[] memory tokens = env_.erc20s(mm_);

        base_ = tokens[bound(baseId, 0, tokens.length - 1)];
        quote_ = tokens[bound(quoteId, 0, tokens.length - 1)];
        vm.assume(base_.token != quote_.token);

        console.log("Network %s, MoneyMarketId %s", toString(network), toString(mm_));
        console.log("Base %s, Quote %s", string(abi.encodePacked((base_.symbol))), string(abi.encodePacked((quote_.symbol))));
    }

    function _quantityAdjustmentOnIncrease(uint256 openLeverage, uint256 increaseLeverage, TSQuote memory increaseQuote, Trade memory trade)
        private
        pure
        returns (int256 adjustment)
    {
        // compensate for actual swap price
        if (
            increaseLeverage > openLeverage && increaseQuote.tradeParams.cashflowCcy == Currency.Base
                && increaseQuote.tradeParams.cashflow < 0
        ) adjustment = trade.swap.output + increaseQuote.tradeParams.cashflow - increaseQuote.quantity - int256(trade.fee);
    }

    function _boundLeverage(uint256 leverage) private view returns (uint256) {
        return bound(leverage, 1e2, 20e2) * 1e16; // 1x to 20x, limited to two decimals numbers
    }

    function _assertLeverage(IMoneyMarketView mmv, PositionId positionId, uint256 expected) internal returns (uint256 leverage) {
        Prices memory prices = mmv.prices(positionId, instrument.base, instrument.quote);
        Balances memory balances = mmv.balances(positionId, instrument.base, instrument.quote);

        uint256 normalisedCollateral = balances.collateral.mulDiv(prices.collateral, instrument.baseUnit);
        uint256 normalisedDebt = balances.debt.mulDiv(prices.debt, instrument.quoteUnit);

        console.log("\n_assertLeverage");
        console.log("collateral %s, debt %s, unit %s", normalisedCollateral, normalisedDebt, prices.unit);

        uint256 margin = (normalisedCollateral - normalisedDebt) * prices.unit / normalisedCollateral;
        leverage = 1e18 * prices.unit / margin;

        console.log("margin %s, leverage %s", margin, leverage);

        console.log("leverage %s, expected %s", leverage, expected);
        // Leverage can be lower due to maxDebt / liquidity constraints
        if (leverage > expected) assertApproxEqRelDecimal(leverage, expected, LEVERAGE_TOLERANCE, 18, "leverage");
    }

    function _assertCashflowInvariants(TSQuote memory quote) internal {
        if (quote.cashflowUsed < 0) {
            if (cashflowCcy == Currency.Quote) {
                assertApproxEqRelDecimal(
                    instrument.quote.balanceOf(TRADER),
                    quote.cashflowUsed.abs(),
                    env.positionActions().slippageTolerance() * 1e14,
                    instrument.quoteDecimals,
                    string.concat("trader quote (", instrument.quote.symbol(), ") withdraw")
                );
            } else {
                assertApproxEqRelDecimal(
                    instrument.base.balanceOf(TRADER),
                    quote.cashflowUsed.abs(),
                    env.positionActions().slippageTolerance() * 1e14,
                    instrument.baseDecimals,
                    string.concat("trader base (", instrument.base.symbol(), ") withdraw")
                );
            }
        } else {
            assertApproxEqAbsDecimal(
                instrument.quote.balanceOf(TRADER),
                0,
                env.bounds(instrument.quoteData.symbol).dust,
                instrument.quoteDecimals,
                string.concat("trader quote (", instrument.quote.symbol(), ") balance")
            );
            assertApproxEqAbsDecimal(
                instrument.base.balanceOf(TRADER),
                0,
                env.bounds(instrument.baseData.symbol).dust,
                instrument.baseDecimals,
                string.concat("trader base (", instrument.base.symbol(), ") balance")
            );
        }
    }

    modifier fuzzTestsEnabled() {
        if (vm.envOr("RUN_FUZZ_TESTS", false)) _;
    }

}

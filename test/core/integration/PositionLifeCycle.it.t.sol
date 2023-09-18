//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

contract PositionLifeCycleIntegration is BaseTest {

    using SafeCast for *;
    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;

    MoneyMarketId mm;

    ERC20Data baseCcy;
    ERC20Data quoteCcy;

    Currency cashflowCcy;

    struct Booleans {
        bool cashflowInQuote;
        bool usePermit;
        bool dustBase;
        bool dustQuote;
    }

    function testFuzzCreatePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 leverage,
        Booleans memory b
    ) public {
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
        leverage = bound(leverage, 1, 20e18);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        env.etchNoFeeModel();
        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        _stubUniswapInfiniteLiquidity();

        (Quote memory quote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);

        assertApproxEqAbsDecimal(
            trade.quantity,
            quote.quantity.toInt256(),
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "trade.quantity"
        );

        assertApproxEqAbsDecimal(
            trade.quantity.toUint256(),
            quote.quantity,
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "trade.quantity"
        );

        PositionStatus memory status = env.quoter().positionStatus(positionId);
        assertApproxEqRelDecimal(status.collateral, quote.quantity, 0.00001e18, instrument.baseDecimals, "variable collateral");
        assertApproxEqRelDecimal(
            status.debt,
            uint256(int256(quote.swapAmount) - (cashflowCcy == Currency.Quote ? quote.cashflowUsed : int256(0))) + quote.transactionFees,
            0.00001e18,
            instrument.quoteDecimals,
            "variable debt"
        );
        _assertLeverage(status.oracleData, leverage > 1e18 ? leverage : 1e18, 0.01e18);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
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
    ) public {
        (env, mm, baseCcy, quoteCcy) = _boundParams(networkId, mmId, baseId, quoteId);
        env.init();
        {
            ERC20Data memory cashflowERC20 = b.cashflowInQuote ? quoteCcy : baseCcy;
            env.positionActions().setUsePermit(b.usePermit && cashflowERC20.hasPermit);

            if (b.dustBase) deal(address(baseCcy.token), address(env.contango()), 1);
            if (b.dustQuote) deal(address(quoteCcy.token), address(env.contango()), 1);
        }
        cashflowCcy = b.cashflowInQuote ? Currency.Quote : Currency.Base;

        quantity = bound(quantity, env.bounds(baseCcy.symbol).min, env.quoter().moneyMarkets(mm).lendingLiquidity(baseCcy.token) / 2);
        leverage = bound(leverage, 1, 20e18);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        env.etchNoFeeModel();
        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        _stubUniswapInfiniteLiquidity();

        (Quote memory openQuote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);
        PositionStatus memory status = env.quoter().positionStatus(positionId);
        _assertLeverage(status.oracleData, leverage > 1e18 ? leverage : 1e18, 0.01e18);

        skip(1 days);
        env.spotStub().movePrice(instrument.baseData, int256(bound(marketMovement, -0.5e18, 100e18)));

        increaseQuantity = bound(increaseQuantity, env.bounds(baseCcy.symbol).min, env.bounds(baseCcy.symbol).max);
        leverage = bound(leverage * 10, 0, 10e18);
        console.log("increase quantity %s, leverage %s, cashflowCcy %s", increaseQuantity, leverage, toString(cashflowCcy));

        Quote memory increaseQuote;
        (increaseQuote, positionId, trade) = env.positionActions().openPosition(positionId, increaseQuantity, leverage, cashflowCcy);
        uint256 totalQty = openQuote.quantity + increaseQuote.quantity;

        assertApproxEqAbsDecimal(
            trade.quantity,
            increaseQuote.quantity.toInt256(),
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "trade.quantity"
        );

        status = env.quoter().positionStatus(positionId);
        assertApproxEqRelDecimal(status.collateral, totalQty, 0.0001e18, instrument.baseDecimals, "variable collateral");
        _assertLeverage(status.oracleData, leverage > 1e18 ? leverage : 1e18, 0.01e18);

        env.checkInvariants(instrument, positionId, openQuote.flashLoanProvider);
        env.checkInvariants(instrument, positionId, increaseQuote.flashLoanProvider);
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
    ) public {
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
        leverage = bound(leverage, 1, 20e18);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        env.etchNoFeeModel();
        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        _stubUniswapInfiniteLiquidity();

        (Quote memory openQuote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);
        PositionStatus memory status = env.quoter().positionStatus(positionId);
        _assertLeverage(status.oracleData, leverage > 1e18 ? leverage : 1e18, 0.01e18);

        skip(1 days);
        env.spotStub().movePrice(instrument.baseData, int256(bound(marketMovement, -0.05e18, 100e18)));

        decreaseQuantity = bound(decreaseQuantity, env.bounds(baseCcy.symbol).min / 50, status.collateral - status.collateral / 10);
        vm.assume(decreaseQuantity < quantity);
        status = env.quoter().positionStatus(positionId);

        leverage = bound(leverage * 10, 0, 10e18);
        console.log("decrease quantity %s, leverage %s, cashflowCcy %s", decreaseQuantity, leverage, toString(cashflowCcy));

        Quote memory decreaseQuote;
        (decreaseQuote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: decreaseQuantity,
            leverage: leverage,
            cashflowCcy: cashflowCcy
        });
        uint256 totalQty = status.collateral - decreaseQuote.quantity;

        assertApproxEqAbsDecimal(
            trade.quantity,
            -decreaseQuote.quantity.toInt256(),
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "trade.quantity"
        );

        status = env.quoter().positionStatus(positionId);
        if (status.collateral > 0) {
            assertApproxEqRelDecimal(status.collateral, totalQty, 0.00001e18, instrument.baseDecimals, "variable collateral");
            _assertLeverage(status.oracleData, leverage > 1e18 ? leverage : 1e18, 0.01e18);
        } else {
            assertApproxEqAbsDecimal(totalQty, 0, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, "closing qty");
        }

        env.checkInvariants(instrument, positionId, openQuote.flashLoanProvider);
        env.checkInvariants(instrument, positionId, decreaseQuote.flashLoanProvider);
        _assertCashflowInvariants(decreaseQuote);
    }

    // function testFuzzFixed() public {
    //     testFuzzDecreasePosition(0, 0, true, 1, 2, 0, 0, 0, -20002000201);
    // }

    function testFuzzClosePosition(
        uint8 networkId,
        uint8 mmId,
        uint8 baseId,
        uint8 quoteId,
        uint256 quantity,
        uint256 leverage,
        int256 marketMovement,
        Booleans memory b
    ) public {
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
        leverage = bound(leverage, 0, 10e18);
        console.log("quantity %s, leverage %s, cashflowCcy %s", quantity, leverage, toString(cashflowCcy));

        env.etchNoFeeModel();
        instrument = env.createInstrument({ baseData: baseCcy, quoteData: quoteCcy });

        _stubUniswapInfiniteLiquidity();

        (Quote memory quote, PositionId positionId, Trade memory trade) =
            env.positionActions().openPosition(instrument.symbol, mm, quantity, leverage, cashflowCcy);

        skip(1 days);
        env.spotStub().movePrice(instrument.baseData, int256(bound(marketMovement, -0.05e18, 100e18)));

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: type(uint256).max,
            cashflow: 0,
            cashflowCcy: cashflowCcy
        });

        assertApproxEqAbsDecimal(
            trade.quantity,
            -quote.quantity.toInt256(),
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "trade.quantity"
        );

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");

        PositionStatus memory status = env.quoter().positionStatus(positionId);
        assertApproxEqRelDecimal(status.collateral, 0, 0.00001e18, instrument.baseDecimals, "variable collateral");
        assertApproxEqRelDecimal(status.debt, 0, 0.00001e18, instrument.quoteDecimals, "variable debt");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
        if (cashflowCcy == Currency.Quote) {
            assertGt(instrument.quote.balanceOf(TRADER), 0, string.concat("trader quote (", instrument.quote.symbol(), ") withdraw"));
        } else {
            assertGt(instrument.base.balanceOf(TRADER), 0, string.concat("trader base (", instrument.base.symbol(), ") withdraw"));
        }
    }

    function _stubUniswapInfiniteLiquidity() private {
        address poolAddress = env.spotStub().stubUniswapPrice({ base: baseCcy, quote: quoteCcy, spread: 0, uniswapFee: 3000 });
        deal(address(baseCcy.token), poolAddress, type(uint160).max);
        deal(address(quoteCcy.token), poolAddress, type(uint160).max);
        deal(address(baseCcy.token), env.balancer(), type(uint160).max);
        deal(address(quoteCcy.token), env.balancer(), type(uint160).max);
    }

    function _boundParams(uint8 networkId, uint8 mmId, uint8 baseId, uint8 quoteId)
        private
        returns (Env env_, MoneyMarketId mm_, ERC20Data memory base_, ERC20Data memory quote_)
    {
        Network network = Network(bound(networkId, uint8(Network.Arbitrum), uint8(Network.Optimism)));
        env_ = provider(network);

        MoneyMarketId[] memory mms = env_.moneyMarkets();
        mm_ = mms[bound(mmId, 0, env_.moneyMarkets().length - 1)];

        ERC20Data[] memory tokens = env_.erc20s(mm_);

        base_ = tokens[bound(baseId, 0, tokens.length - 1)];
        quote_ = tokens[bound(quoteId, 0, tokens.length - 1)];
        vm.assume(base_.token != quote_.token);

        console.log("Network %s, MoneyMarketId %s", toString(network), MoneyMarketId.unwrap(mm_));
        console.log("Base %s, Quote %s", string(abi.encodePacked((base_.symbol))), string(abi.encodePacked((quote_.symbol))));
    }

    function _assertLeverage(OracleData memory oracleData, uint256 expected, uint256 tolerance) internal returns (uint256 leverage) {
        console.log("\n_assertLeverage");
        console.log("collateral %s, debt %s, unit %s", oracleData.collateral, oracleData.debt, oracleData.unit);

        uint256 margin = (oracleData.collateral - oracleData.debt) * oracleData.unit / oracleData.collateral;
        leverage = 1e18 * oracleData.unit / margin;

        console.log("margin %s, leverage %s", margin, leverage);

        // Leverage can be lower due to maxDebt / liquidity constraints
        if (leverage > expected) assertApproxEqRelDecimal(leverage, expected, tolerance, 18, "leverage");
        console.log("leverage %s, expected %s", leverage, expected);
    }

    function _assertCashflowInvariants(Quote memory quote) internal {
        if (quote.cashflowUsed < 0) {
            if (cashflowCcy == Currency.Quote) {
                assertApproxEqRelDecimal(
                    instrument.quote.balanceOf(TRADER),
                    quote.cashflowUsed.abs(),
                    DEFAULT_SLIPPAGE_TOLERANCE * 1e14,
                    instrument.quoteDecimals,
                    string.concat("trader quote (", instrument.quote.symbol(), ") withdraw")
                );
            } else {
                assertApproxEqRelDecimal(
                    instrument.base.balanceOf(TRADER),
                    quote.cashflowUsed.abs(),
                    DEFAULT_SLIPPAGE_TOLERANCE * 1e14,
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

}

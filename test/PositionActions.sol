// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/StdJson.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "src/core/Maestro.sol";
import "src/interfaces/IContango.sol";
import "src/interfaces/IVault.sol";
import "./Quoter.sol";

import "script/constants.sol";

import "./dependencies/Uniswap.sol";
import "./TestHelper.sol";
import "./TestSetup.t.sol";

struct OpenQuote {
    uint256 quantity;
    Currency swapCcy;
    uint256 swapAmount;
    uint256 price;
    int256 cashflowUsed;
}

contract PositionActions {

    using stdJson for string;
    using SafeCast for *;
    using SignedMath for *;

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    TestHelper private immutable helper;
    Env private immutable env;
    address private immutable trader;
    uint256 private immutable traderPk;

    uint256 globalSlippageTolerance = DEFAULT_SLIPPAGE_TOLERANCE;
    IERC20 nativeTokenWrapper;
    bool usePermit;
    EIP2098Permit signedPermit;
    uint32 expiry = PERP;

    constructor(TestHelper _helper, Env _env, address _trader, uint256 _traderPk) {
        helper = _helper;
        env = _env;
        trader = _trader;
        traderPk = _traderPk;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) public {
        globalSlippageTolerance = _slippageTolerance;
    }

    function setNativeTokenWrapper(IERC20 _nativeTokenWrapper) public {
        nativeTokenWrapper = _nativeTokenWrapper;
    }

    function setUsePermit(bool _usePermit) public {
        usePermit = _usePermit;
    }

    function setExpiry(uint32 _expiry) public {
        expiry = _expiry;
    }

    function quoteOpenPosition(PositionId positionId, uint256 quantity, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote)
    {
        quote = env.quoter().quoteOpen(
            OpenQuoteParams({
                positionId: positionId,
                quantity: quantity,
                leverage: leverage,
                cashflow: cashflow,
                cashflowCcy: cashflowCcy,
                slippageTolerance: globalSlippageTolerance
            })
        );
    }

    // function quoteOpenPositionTS(
    //     PositionId positionId,
    //     uint256 quantity,
    //     uint256 leverage,
    //     int256 cashflow,
    //     Currency cashflowCcy
    // ) public returns (Quote memory quote) {
    //     Balances memory balances;
    //     NormalisedBalances memory normalisedBalances;
    //     Instrument memory instrument;
    //     Prices memory prices;
    //     IMoneyMarket moneyMarket;
    //     {
    //         (Symbol symbol, MoneyMarketId mm,, uint256 positionN) = positionId.decode();
    //         instrument = env.contango().instrument(symbol);
    //         moneyMarket = env.contango().positionFactory().moneyMarket(mm);

    //         if (positionN > 0) {
    //             balances = moneyMarket.balances(positionId, instrument.base, instrument.quote);
    //             normalisedBalances = moneyMarket.normalisedBalances(positionId, instrument.base, instrument.quote);
    //         }

    //         prices = moneyMarket.prices(symbol, instrument.base, instrument.quote);
    //     }

    //     string memory params = "";
    //     VM.serializeUint(params, "quantity", quantity);
    //     VM.serializeUint(params, "slippageTolerance", globalSlippageTolerance);
    //     VM.serializeUint(params, "cashflowCcy", uint8(cashflowCcy));
    //     VM.serializeInt(params, "cashflow", cashflow);
    //     VM.serializeUint(params, "instrument.baseUnit", instrument.baseUnit);
    //     VM.serializeUint(params, "instrument.quoteUnit", instrument.quoteUnit);
    //     VM.serializeUint(params, "prices.collateral", prices.collateral);
    //     VM.serializeUint(params, "prices.debt", prices.debt);
    //     VM.serializeUint(params, "prices.unit", prices.unit);
    //     VM.serializeUint(params, "balances.collateral", balances.collateral);
    //     VM.serializeUint(params, "balances.debt", balances.debt);
    //     VM.serializeUint(params, "normalisedBalances.collateral", normalisedBalances.collateral);
    //     VM.serializeUint(params, "normalisedBalances.debt", normalisedBalances.debt);
    //     VM.serializeUint(params, "normalisedBalances.unit", normalisedBalances.unit);
    //     VM.serializeUint(params, "liquidity.borrowingLiquidity", moneyMarket.borrowingLiquidity(instrument.quote));
    //     VM.serializeUint(params, "liquidity.lendingLiquidity", moneyMarket.lendingLiquidity(instrument.base));
    //     params = VM.serializeUint(params, "leverage", leverage);

    //     VM.writeJson(params, string.concat(VM.projectRoot(), "/json-test/input.json"));

    //     // npx ts-node quoter.ts quote-open -i json-test/input.json -o json-test/output.json
    //     uint256 arg;
    //     string[] memory cli = new string[](8);
    //     cli[arg++] = "npx";
    //     cli[arg++] = "ts-node";
    //     cli[arg++] = "quoter.ts";
    //     cli[arg++] = "quote-open";
    //     cli[arg++] = "-i";
    //     cli[arg++] = string.concat(VM.projectRoot(), "/json-test/input.json");
    //     cli[arg++] = "-o";
    //     cli[arg++] = string.concat(VM.projectRoot(), "/json-test/output.json");
    //     VM.ffi(cli);

    //     string memory json = VM.readFile(string.concat(VM.projectRoot(), "/json-test/output.json"));

    //     quote.quantity = json.readUint("$.quantity");
    //     quote.swapCcy = Currency(json.readUint("$.swapCcy"));
    //     quote.swapAmount = json.readUint("$.swapAmount");
    //     quote.cashflowUsed = json.readInt("$.cashflowUsed");
    //     quote.price = json.readUint("$.price");
    // }

    function openPosition(Symbol symbol, MoneyMarketId mm, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote =
            quoteOpenPosition({ positionId: newPositionId, quantity: quantity, leverage: leverage, cashflow: 0, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: newPositionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(newPositionId, quote, cashflowCcy)
        });
    }

    function openPosition(Symbol symbol, MoneyMarketId mm, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote =
            quoteOpenPosition({ positionId: newPositionId, quantity: quantity, leverage: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: newPositionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(newPositionId, quote, cashflowCcy)
        });
    }

    function openPosition(
        Symbol symbol,
        MoneyMarketId mm,
        uint256 quantity,
        int256 cashflow,
        Currency cashflowCcy,
        uint256 slippageTolerance
    ) public returns (Quote memory quote, PositionId positionId_, Trade memory trade) {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote =
            quoteOpenPosition({ positionId: newPositionId, quantity: quantity, leverage: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: newPositionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: slippageTolerance,
            quote: quote,
            swapBytes: prepareOpenPosition(newPositionId, quote, cashflowCcy)
        });
    }

    function openPosition(Symbol symbol, MoneyMarketId mm, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote =
            quoteOpenPosition({ positionId: newPositionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: newPositionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(newPositionId, quote, cashflowCcy)
        });
    }

    function openPosition(PositionId positionId, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteOpenPosition({ positionId: positionId, quantity: quantity, leverage: leverage, cashflow: 0, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(positionId, quote, cashflowCcy)
        });
    }

    function openPosition(PositionId positionId, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteOpenPosition({ positionId: positionId, quantity: quantity, leverage: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(positionId, quote, cashflowCcy)
        });
    }

    function openPosition(PositionId positionId, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteOpenPosition({ positionId: positionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = openPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(positionId, quote, cashflowCcy)
        });
    }

    function openPosition(PositionId positionId, uint256 quantity, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteOpenPosition({
            positionId: positionId,
            quantity: quantity,
            leverage: leverage,
            cashflow: cashflow,
            cashflowCcy: cashflowCcy
        });
        (positionId_, trade) = openPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: prepareOpenPosition(positionId, quote, cashflowCcy)
        });
    }

    function prepareOpenPosition(PositionId positionId, Quote memory quote, Currency cashflowCcy) public returns (bytes memory swapBytes) {
        TestInstrument memory instrument = env.instruments(positionId.getSymbol());
        _deal(instrument, cashflowCcy, quote.cashflowUsed);

        if (quote.swapCcy == Currency.Quote) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        } else if (quote.swapCcy == Currency.Base) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        }
    }

    function openPosition(
        Quote memory quote,
        PositionId positionId,
        Currency cashflowCcy,
        uint256 slippageTolerance,
        bytes memory swapBytes
    ) public returns (PositionId positionId_, Trade memory trade) {
        uint256 limitPrice = quote.price * (1e4 + slippageTolerance) / 1e4;
        if (quote.cashflowUsed >= 0) {
            console.log("Open position: qty %s, cashflow: %s, limitPrice: %s", quote.quantity, uint256(quote.cashflowUsed), limitPrice);
        } else {
            console.log("Open position: qty %s, cashflow: -%s, limitPrice: %s", quote.quantity, uint256(-quote.cashflowUsed), limitPrice);
        }

        (IERC20 _cashflowToken, uint256 value) = prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        TradeParams memory params = TradeParams({
            positionId: positionId,
            quantity: quote.quantity.toInt256(),
            cashflowCcy: cashflowCcy,
            cashflow: quote.cashflowUsed,
            limitPrice: limitPrice
        });
        ExecutionParams memory executionParams = ExecutionParams({
            router: env.uniswap(),
            spender: env.uniswap(),
            swapAmount: quote.swapAmount,
            swapBytes: swapBytes,
            flashLoanProvider: quote.flashLoanProvider
        });

        (positionId_, trade) = executeTrade(params, executionParams, _cashflowToken, value);
    }

    function quoteClosePosition(PositionId positionId, uint256 quantity, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote)
    {
        quote = env.quoter().quoteClose(
            CloseQuoteParams({
                positionId: positionId,
                quantity: quantity,
                leverage: leverage,
                cashflow: cashflow,
                cashflowCcy: cashflowCcy,
                slippageTolerance: globalSlippageTolerance
            })
        );
    }

    function closePosition(PositionId positionId, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote, Trade memory trade)
    {
        quote =
            quoteClosePosition({ positionId: positionId, quantity: quantity, leverage: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
        bytes memory swapBytes = prepareClosePosition(positionId, quote, cashflowCcy);
        trade = closePosition({ quote: quote, positionId: positionId, cashflowCcy: cashflowCcy, swapBytes: swapBytes });
    }

    function closePosition(PositionId positionId, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, Trade memory trade)
    {
        quote =
            quoteClosePosition({ positionId: positionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        bytes memory swapBytes = prepareClosePosition(positionId, quote, cashflowCcy);
        trade = closePosition({ quote: quote, positionId: positionId, cashflowCcy: cashflowCcy, swapBytes: swapBytes });
    }

    function closePosition(PositionId positionId, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (Quote memory quote, Trade memory trade)
    {
        quote =
            quoteClosePosition({ positionId: positionId, quantity: quantity, leverage: leverage, cashflow: 0, cashflowCcy: cashflowCcy });
        bytes memory swapBytes = prepareClosePosition(positionId, quote, cashflowCcy);
        trade = closePosition({ quote: quote, positionId: positionId, cashflowCcy: cashflowCcy, swapBytes: swapBytes });
    }

    function prepareClosePosition(PositionId positionId, Quote memory quote, Currency cashflowCcy)
        public
        returns (bytes memory swapBytes)
    {
        TestInstrument memory instrument = env.instruments(positionId.getSymbol());
        _deal(instrument, cashflowCcy, quote.cashflowUsed);

        if (quote.swapCcy == Currency.Quote) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        } else if (quote.swapCcy == Currency.Base) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        }
    }

    function closePosition(Quote memory quote, PositionId positionId, Currency cashflowCcy, bytes memory swapBytes)
        public
        returns (Trade memory trade)
    {
        uint256 limitPrice = quote.price * (1e4 - DEFAULT_SLIPPAGE_TOLERANCE) / 1e4;
        if (quote.cashflowUsed >= 0) {
            console.log("Close position: qty %s, cashflow: %s, limitPrice: %s", quote.quantity, uint256(quote.cashflowUsed), limitPrice);
        } else {
            console.log("Close position: qty %s, cashflow: -%s, limitPrice: %s", quote.quantity, uint256(-quote.cashflowUsed), limitPrice);
        }

        (IERC20 _cashflowToken, uint256 value) = prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        TradeParams memory params = TradeParams({
            positionId: positionId,
            quantity: quote.fullyClose ? type(int256).min : -quote.quantity.toInt256(),
            cashflowCcy: cashflowCcy,
            cashflow: quote.cashflowUsed,
            limitPrice: limitPrice
        });
        ExecutionParams memory executionParams = ExecutionParams({
            router: env.uniswap(),
            spender: env.uniswap(),
            swapAmount: quote.swapAmount,
            swapBytes: swapBytes,
            flashLoanProvider: quote.flashLoanProvider
        });

        (, trade) = executeTrade(params, executionParams, _cashflowToken, value);
    }

    function quoteModifyPosition(PositionId positionId, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (Quote memory quote)
    {
        quote = env.quoter().quoteModify(
            ModifyQuoteParams({ positionId: positionId, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy })
        );
    }

    function modifyPosition(PositionId positionId, int256 cashflow, Currency cashflowCcy) public returns (Quote memory quote) {
        quote = quoteModifyPosition({ positionId: positionId, leverage: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
        bytes memory swapBytes = prepareModifyPosition(positionId, quote, cashflowCcy);
        modifyPosition({ quote: quote, positionId: positionId, cashflowCcy: cashflowCcy, swapBytes: swapBytes });
    }

    function modifyPosition(PositionId positionId, uint256 leverage, Currency cashflowCcy) public returns (Quote memory quote) {
        quote = quoteModifyPosition({ positionId: positionId, leverage: leverage, cashflow: 0, cashflowCcy: cashflowCcy });
        bytes memory swapBytes = prepareModifyPosition(positionId, quote, cashflowCcy);
        modifyPosition({ quote: quote, positionId: positionId, cashflowCcy: cashflowCcy, swapBytes: swapBytes });
    }

    function prepareModifyPosition(PositionId positionId, Quote memory quote, Currency cashflowCcy)
        public
        returns (bytes memory swapBytes)
    {
        TestInstrument memory instrument = env.instruments(positionId.getSymbol());
        _deal(instrument, cashflowCcy, quote.cashflowUsed);

        if (quote.swapCcy == Currency.Quote) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        } else if (quote.swapCcy == Currency.Base) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                    recipient: address(env.contango().spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        }
    }

    function modifyPosition(Quote memory quote, PositionId positionId, Currency cashflowCcy, bytes memory swapBytes)
        public
        returns (Trade memory trade)
    {
        uint256 limitPrice;
        if (quote.cashflowUsed >= 0) {
            limitPrice = quote.price * (1e4 - DEFAULT_SLIPPAGE_TOLERANCE) / 1e4;
            console.log("Modify position: cashflow: %s", uint256(quote.cashflowUsed));
        } else {
            limitPrice = quote.price * (1e4 + DEFAULT_SLIPPAGE_TOLERANCE) / 1e4;
            console.log("Modify position: cashflow: -%s", uint256(-quote.cashflowUsed));
        }

        (IERC20 _cashflowToken, uint256 value) = prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        TradeParams memory params = TradeParams({
            positionId: positionId,
            quantity: 0,
            cashflowCcy: cashflowCcy,
            cashflow: quote.cashflowUsed,
            limitPrice: limitPrice
        });
        ExecutionParams memory executionParams = ExecutionParams({
            router: env.uniswap(),
            spender: env.uniswap(),
            swapAmount: quote.swapAmount,
            swapBytes: swapBytes,
            flashLoanProvider: quote.flashLoanProvider
        });

        (, trade) = executeTrade(params, executionParams, _cashflowToken, value);
    }

    function _deal(TestInstrument memory instrument, Currency cashflowCcy, int256 cashflowUsed) internal {
        if (cashflowUsed > 0) {
            IERC20 _cashflowToken = cashflowCcy == Currency.Quote ? instrument.quote : instrument.base;
            if (_cashflowToken == nativeTokenWrapper) {
                VM.deal(trader, uint256(cashflowUsed));
            } else if (usePermit) {
                signedPermit = env.dealAndPermit(_cashflowToken, trader, traderPk, uint256(cashflowUsed), address(env.vault()));
            } else {
                env.dealAndApprove(_cashflowToken, trader, uint256(cashflowUsed), address(env.vault()));
            }
        } else {
            delete signedPermit;
        }
    }

    function prepareCashflow(PositionId positionId, Currency cashflowCcy, int256 cashflowUsed)
        public
        view
        returns (IERC20 _cashflowToken, uint256 value)
    {
        TestInstrument memory instrument = env.instruments(positionId.getSymbol());
        _cashflowToken = cashflowCcy == Currency.Quote ? instrument.quote : instrument.base;
        value = cashflowUsed > 0 && _cashflowToken == nativeTokenWrapper ? uint256(cashflowUsed) : 0;
    }

    function executeTrade(TradeParams memory params, ExecutionParams memory executionParams, IERC20 _cashflowToken, uint256 value)
        public
        returns (PositionId positionId_, Trade memory trade)
    {
        if (env.canPrank()) VM.startPrank(trader);
        else VM.startBroadcast(trader);

        if (params.cashflow > 0) {
            if (signedPermit.amount != 0) {
                (positionId_, trade) = env.maestro().depositAndTradeWithPermit(params, executionParams, signedPermit);
            } else {
                (positionId_, trade) = env.maestro().depositAndTrade{ value: value }(params, executionParams);
            }
        }
        if (params.cashflow < 0) {
            if (_cashflowToken == nativeTokenWrapper) {
                (positionId_, trade,) = env.maestro().tradeAndWithdrawNative(params, executionParams, trader);
            } else {
                (positionId_, trade,) = env.maestro().tradeAndWithdraw(params, executionParams, trader);
            }
        }
        if (params.cashflow == 0) (positionId_, trade) = env.maestro().trade(params, executionParams);

        if (env.canPrank()) VM.stopPrank();
        else VM.stopBroadcast();
    }

}

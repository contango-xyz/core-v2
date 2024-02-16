// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/StdJson.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "src/core/Maestro.sol";
import "src/interfaces/IContango.sol";
import "src/interfaces/IVault.sol";

import "script/constants.sol";

import "./dependencies/Uniswap.sol";
import "./dependencies/Strings2.sol";
import "./TestSetup.t.sol";
import "./TSQuoter.sol";

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
    using Strings2 for bytes;

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    Env private immutable env;
    address private immutable trader;
    uint256 private immutable traderPk;
    uint256 globalSlippageTolerance = DEFAULT_SLIPPAGE_TOLERANCE * 1e14;
    IERC20 nativeTokenWrapper;
    bool usePermit;
    EIP2098Permit signedPermit;
    uint32 expiry = PERP;
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    constructor(Env _env, address _trader, uint256 _traderPk) {
        env = _env;
        trader = _trader;
        traderPk = _traderPk;
    }

    function setSlippageTolerance(uint256 _slippageTolerance) public {
        globalSlippageTolerance = _slippageTolerance * 1e14;
    }

    function slippageTolerance() public view returns (uint256) {
        return globalSlippageTolerance / 1e14;
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

    function quoteTrade(PositionId positionId, int256 quantity, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote)
    {
        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: quantity,
            leverage: leverage,
            cashflow: cashflow,
            cashflowCcy: cashflowCcy,
            slippageTolerance: globalSlippageTolerance
        });
    }

    function quoteWithLeverage(PositionId positionId, int256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote)
    {
        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: int256(quantity),
            leverage: leverage,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: globalSlippageTolerance
        });
    }

    function quoteWithCashflow(PositionId positionId, int256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote)
    {
        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: quantity,
            leverage: 0,
            cashflow: cashflow,
            cashflowCcy: cashflowCcy,
            slippageTolerance: globalSlippageTolerance
        });
    }

    function quoteModify(PositionId positionId, int256 quantity, Currency cashflowCcy) public returns (TSQuote memory quote) {
        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: quantity,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: globalSlippageTolerance
        });
    }

    function quoteFullyClose(PositionId positionId, Currency cashflowCcy) public returns (TSQuote memory quote) {
        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: type(int256).min,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: globalSlippageTolerance
        });
    }

    function submitTrade(PositionId positionId, TSQuote memory quote, Currency cashflowCcy)
        public
        returns (PositionId _positionId, Trade memory trade)
    {
        TestInstrument memory instrument = env.instruments(positionId.getSymbol());
        _deal(instrument, cashflowCcy, quote.cashflowUsed);
        (IERC20 _cashflowToken, uint256 value) = prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);
        (_positionId, trade) = executeTrade(quote.tradeParams, quote.execParams, _cashflowToken, value);
    }

    function openPosition(Symbol symbol, MoneyMarketId mm, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote = quoteWithLeverage({ positionId: newPositionId, quantity: int256(quantity), leverage: leverage, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: newPositionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(Symbol symbol, MoneyMarketId mm, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote = quoteWithCashflow({ positionId: newPositionId, quantity: int256(quantity), cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: newPositionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(
        Symbol symbol,
        MoneyMarketId mm,
        uint256 quantity,
        int256 cashflow,
        Currency cashflowCcy,
        uint256 _slippageTolerance
    ) public returns (TSQuote memory quote, PositionId positionId_, Trade memory trade) {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote = env.tsQuoter().quote({
            positionId: newPositionId,
            quantity: int256(quantity),
            leverage: 0,
            cashflow: cashflow,
            cashflowCcy: cashflowCcy,
            slippageTolerance: _slippageTolerance
        });
        (positionId_, trade) = submitTrade({ positionId: newPositionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(Symbol symbol, MoneyMarketId mm, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        PositionId newPositionId = env.encoder().encodePositionId(symbol, mm, expiry, 0);
        quote = quoteTrade({ positionId: newPositionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: newPositionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(PositionId positionId, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteWithLeverage({ positionId: positionId, quantity: int256(quantity), leverage: leverage, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(PositionId positionId, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteWithCashflow({ positionId: positionId, quantity: int256(quantity), cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(PositionId positionId, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteTrade({ positionId: positionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        (positionId_, trade) = submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(PositionId positionId, uint256 quantity, uint256 leverage, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, PositionId positionId_, Trade memory trade)
    {
        quote = quoteTrade({
            positionId: positionId,
            quantity: int256(quantity),
            leverage: leverage,
            cashflow: cashflow,
            cashflowCcy: cashflowCcy
        });
        (positionId_, trade) = submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });
    }

    function openPosition(TSQuote memory quote, PositionId positionId, Currency cashflowCcy)
        public
        returns (PositionId positionId_, Trade memory trade)
    {
        (positionId_, trade) = submitTrade(positionId, quote, cashflowCcy);
    }

    function modifyPosition(PositionId positionId, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, Trade memory trade)
    {
        (quote,, trade) = openPosition({ positionId: positionId, quantity: 0, cashflow: cashflow, cashflowCcy: cashflowCcy });
    }

    function closePosition(PositionId positionId, uint256 quantity, int256 cashflow, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, Trade memory trade)
    {
        quote = quoteWithCashflow({ positionId: positionId, quantity: -int256(quantity), cashflow: cashflow, cashflowCcy: cashflowCcy });
        trade = closePosition(positionId, quote, cashflowCcy);
    }

    function closePosition(PositionId positionId, int256 cashflow, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, Trade memory trade)
    {
        quote = quoteTrade({ positionId: positionId, quantity: 0, leverage: leverage, cashflow: cashflow, cashflowCcy: cashflowCcy });
        trade = closePosition(positionId, quote, cashflowCcy);
    }

    function closePosition(PositionId positionId, uint256 quantity, uint256 leverage, Currency cashflowCcy)
        public
        returns (TSQuote memory quote, Trade memory trade)
    {
        quote = quoteWithLeverage({ positionId: positionId, quantity: -int256(quantity), leverage: leverage, cashflowCcy: cashflowCcy });
        trade = closePosition(positionId, quote, cashflowCcy);
    }

    function closePosition(PositionId positionId, TSQuote memory quote, Currency cashflowCcy) public returns (Trade memory trade) {
        (, trade) = submitTrade(positionId, quote, cashflowCcy);
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

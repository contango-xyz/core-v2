// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./TestSetup.t.sol";
import "./dependencies/Strings2.sol";

import "src/core/Contango.sol";
import "src/moneymarkets/ContangoLens.sol";

struct TSQuote {
    TradeParams tradeParams;
    ExecutionParams execParams;
    int256 quantity;
    int256 cashflowUsed;
    uint256 price;
    bool fullyClosing;
    uint256 transactionFees;
}

contract TSQuoter {

    using Strings2 for bytes;
    using SignedMath for int256;

    struct Liquidity {
        uint256 borrowingLiquidity;
        uint256 lendingLiquidity;
    }

    struct Ltv {
        uint256 ltv;
        uint256 liquidationThreshold;
    }

    struct NormalisedBalances {
        uint256 collateral;
        uint256 debt;
        uint256 unit;
    }

    struct Token {
        address addr;
        string symbol;
        string name;
        uint256 decimals;
        uint256 unit;
    }

    struct TSInstrument {
        bool closingOnly;
        Token base;
        Token quote;
    }

    struct TSMetaParams {
        TSInstrument instrument;
        Prices prices;
        Balances balances;
        NormalisedBalances normalisedBalances;
        Liquidity liquidity;
        Ltv ltv;
        uint256 fee;
        Limits limits;
    }

    struct LiquidityBuffer {
        uint256 lending;
        uint256 borrowing;
    }

    struct TSQuoteParams {
        PositionId positionId;
        int256 quantity;
        uint256 leverage;
        int256 cashflow;
        Currency cashflowCcy;
        uint256 slippageTolerance;
        TSMetaParams meta;
        IERC7399 flashLoanProvider;
        uint256 flashFee;
        address spotExecutor;
        LiquidityBuffer liquidityBuffer;
        bool flashBorrowSupported;
    }

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Contango internal immutable contango;
    ContangoLens public immutable contangoLens;

    IERC7399[] public flashLoanProviders;
    LiquidityBuffer public liquidityBuffer;

    constructor(Contango _contango, ContangoLens _contangoLens) {
        contango = _contango;
        contangoLens = _contangoLens;
    }

    function addFlashLoanProvider(IERC7399 _provider) external {
        flashLoanProviders.push(_provider);
    }

    function removeAllFlashLoanProviders() external {
        uint256 length = flashLoanProviders.length;
        for (uint256 i = 0; i < length; i++) {
            flashLoanProviders.pop();
        }
    }

    function setLiquidityBuffer(LiquidityBuffer memory _liquidityBuffer) external {
        liquidityBuffer = _liquidityBuffer;
    }

    function quote(
        PositionId positionId,
        int256 quantity,
        uint256 leverage,
        int256 cashflow,
        Currency cashflowCcy,
        uint256 slippageTolerance
    ) external returns (TSQuote memory result) {
        return quoteRealDex(positionId, quantity, leverage, cashflow, cashflowCcy, slippageTolerance, "uniswap-single-pool");
    }

    function quoteRealDex(
        PositionId positionId,
        int256 quantity,
        uint256 leverage,
        int256 cashflow,
        Currency cashflowCcy,
        uint256 slippageTolerance,
        string memory dex
    ) public returns (TSQuote memory result) {
        Instrument memory instrument;
        TSQuoteParams memory tsQuoteParams;
        {
            (Symbol symbol,,,) = positionId.decode();
            instrument = contango.instrument(symbol);
            tsQuoteParams.meta.instrument = TSInstrument({
                base: Token({
                    addr: address(instrument.base),
                    symbol: instrument.base.symbol(),
                    name: instrument.base.name(),
                    decimals: instrument.base.decimals(),
                    unit: instrument.baseUnit
                }),
                quote: Token({
                    addr: address(instrument.quote),
                    symbol: instrument.quote.symbol(),
                    name: instrument.quote.name(),
                    decimals: instrument.quote.decimals(),
                    unit: instrument.quoteUnit
                }),
                closingOnly: instrument.closingOnly
            });
            tsQuoteParams.meta.balances = contangoLens.balances(positionId);
            tsQuoteParams.meta.prices = contangoLens.prices(positionId);
        }

        (tsQuoteParams.meta.liquidity.borrowingLiquidity, tsQuoteParams.meta.liquidity.lendingLiquidity) =
            contangoLens.liquidity(positionId);

        tsQuoteParams.meta.limits = contangoLens.limits(positionId);

        (tsQuoteParams.meta.ltv.ltv, tsQuoteParams.meta.ltv.liquidationThreshold) = contangoLens.thresholds(positionId);
        tsQuoteParams.quantity = quantity;
        tsQuoteParams.leverage = leverage;
        tsQuoteParams.cashflow = cashflow;
        tsQuoteParams.cashflowCcy = cashflowCcy;
        tsQuoteParams.slippageTolerance = slippageTolerance;
        tsQuoteParams.spotExecutor = address(contango.spotExecutor());
        tsQuoteParams.positionId = positionId;
        tsQuoteParams.liquidityBuffer = liquidityBuffer;

        {
            (, MoneyMarketId mm,,) = positionId.decode();
            bool flashBorrowSupported = contango.positionFactory().moneyMarket(mm).supportsInterface(type(IFlashBorrowProvider).interfaceId);
            if (quantity > 0 && flashBorrowSupported) {
                tsQuoteParams.flashFee = 0;
            } else {
                // // TODO be smarter
                // (IERC7399 _provider, uint256 minFee) = _flashLoanProvider(instrument.base, quantity.abs());
                // tsQuoteParams.flashLoanProvider = _provider;
                // // TODO check this math
                // tsQuoteParams.flashFee = minFee * quantity.abs() / instrument.baseUnit;
                tsQuoteParams.flashLoanProvider = flashLoanProviders[0];
                // TODO hack to get flash loan fee in WAD %
                uint256 flashFee = tsQuoteParams.flashLoanProvider.flashFee(address(instrument.base), 10 ** instrument.base.decimals());
                tsQuoteParams.flashFee = instrument.base.decimals() == 18
                    ? flashFee
                    : instrument.base.decimals() > 18
                        ? flashFee / (10 ** (instrument.base.decimals() - 18))
                        : flashFee * (10 ** (18 - instrument.base.decimals()));
            }
        }

        uint256 idx;
        string[] memory cli = new string[](12);
        cli[idx++] = "npm";
        cli[idx++] = "run";
        cli[idx++] = "--silent";
        cli[idx++] = "cli:quote";
        cli[idx++] = "-w";
        cli[idx++] = "sdk";
        cli[idx++] = "--";
        cli[idx++] = "--dex";
        cli[idx++] = dex;
        cli[idx++] = "--chainId";
        cli[idx++] = vm.toString(block.chainid);
        cli[idx++] = abi.encodeWithSelector(this.____tsQuote.selector, tsQuoteParams).toHexString();
        bytes memory _result = vm.ffi(cli);

        result = abi.decode(_result, (TSQuote));
    }

    function ____tsQuote(TSQuoteParams memory params) public returns (TSQuote memory) { }

    function _flashLoanProvider(IERC20 asset, uint256 amount) internal view returns (IERC7399 _provider, uint256 minFee) {
        minFee = type(uint256).max;
        for (uint256 i = 0; i < flashLoanProviders.length; i++) {
            IERC7399 p = flashLoanProviders[i];
            uint256 fee = p.flashFee(address(asset), amount);

            console.log("asset", address(asset));
            console.log("amount", amount);
            console.log("fee", fee);
            console.log("minFee", minFee);
            console.log("p", address(p));

            if (fee < minFee) {
                minFee = fee;
                _provider = p;
            }
            if (minFee == 0) break;
        }

        require(minFee != type(uint256).max, "no flash loan provider");
    }

}

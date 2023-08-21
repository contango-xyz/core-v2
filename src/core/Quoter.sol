//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../dependencies/Uniswap.sol";

import "../interfaces/IQuoter.sol";
import "../interfaces/IContango.sol";
import "../libraries/MathLib.sol";

/// @title Contract for quoting position operations
contract Quoter is IQuoter {

    using MathLib for *;
    using SafeCast for *;
    using Math for *;
    using SignedMath for *;
    using QuoterHelper for *;

    struct FU2Deep {
        PositionId positionId;
        Symbol symbol;
        Instrument instrument;
        address positionOwner;
        uint256 positionN;
        uint256 flashLoanQuantity;
        MoneyMarket mm;
        IMoneyMarketView moneyMarket;
        Prices prices;
        uint256 slippageTolerance;
        bool opening;
    }

    IContango public immutable contango;
    PositionNFT public immutable positionNFT;

    mapping(MoneyMarket => IMoneyMarketView) public moneyMarkets;
    IERC7399[] public flashLoanProviders;

    constructor(IContango _contango) {
        contango = _contango;
        positionNFT = _contango.positionNFT();
    }

    function setMoneyMarket(IMoneyMarketView moneyMarketView) external {
        moneyMarkets[moneyMarketView.moneyMarketId()] = moneyMarketView;
    }

    function addFlashLoanProvider(IERC7399 provider) external {
        flashLoanProviders.push(provider);
    }

    function removeAllFlashLoanProviders() external {
        uint256 length = flashLoanProviders.length;
        for (uint256 i = 0; i < length; i++) {
            flashLoanProviders.pop();
        }
    }

    function positionStatus(PositionId positionId) external returns (PositionStatus memory) {
        (Symbol symbol,,,) = positionId.decode();
        Instrument memory instrument = contango.instrument(symbol);

        IMoneyMarketView moneyMarket = moneyMarkets[positionId.getMoneyMarket()];

        Balances memory balances = moneyMarket.balances(positionId, instrument.base, instrument.quote);
        NormalisedBalances memory normalisedBalances = moneyMarket.normalisedBalances(positionId, instrument.base, instrument.quote);

        return PositionStatus({
            collateral: balances.collateral,
            debt: balances.debt,
            oracleData: OracleData({ collateral: normalisedBalances.collateral, debt: normalisedBalances.debt, unit: normalisedBalances.unit })
        });
    }

    modifier onlyOneIsZero(OpenQuoteParams memory params) {
        // if ((params.quantity == 0 ? 1 : 0) + (params.cashflow == 0 ? 1 : 0) + (params.leverage == 0 ? 1 : 0) != 1) {
        //     revert("one must be zero");
        // }
        _;
    }

    /// @inheritdoc IQuoter
    function quoteOpen(OpenQuoteParams memory params) external onlyOneIsZero(params) returns (Quote memory quote) {
        // console.log("\nquoteOpen");
        FU2Deep memory vars;
        vars.slippageTolerance = params.slippageTolerance;
        vars.opening = true;
        vars.positionId = params.positionId;

        (vars.symbol, vars.mm,, vars.positionN) = params.positionId.decode();
        vars.instrument = contango.instrument(vars.symbol);

        Balances memory balances;
        NormalisedBalances memory normalisedBalances;
        if (vars.positionN > 0) {
            vars.moneyMarket = moneyMarkets[params.positionId.getMoneyMarket()];
            vars.positionOwner = positionNFT.positionOwner(params.positionId);
            balances = vars.moneyMarket.balances(params.positionId, vars.instrument.base, vars.instrument.quote);
            normalisedBalances = vars.moneyMarket.normalisedBalances(params.positionId, vars.instrument.base, vars.instrument.quote);
        } else {
            vars.moneyMarket = moneyMarkets[vars.mm];
        }

        vars.prices = vars.moneyMarket.prices(vars.symbol, vars.instrument.base, vars.instrument.quote);

        // console.log("params.cashflowCcy", params.cashflowCcy.toString());
        // console.log("params.cashflow %s%s", params.cashflow < 0 ? "-" : "", params.cashflow.abs());
        // console.log("params.quantity", params.quantity);
        // console.log("params.leverage", params.leverage);
        quote.price = vars.instrument.quoteUnit * vars.prices.collateral / vars.prices.debt;
        // console.log("quote.price", quote.price);
        // console.log("balances.collateral", balances.collateral);
        // console.log("normalisedBalances.collateral", normalisedBalances.collateral);
        // console.log("prices.collateral", vars.prices.collateral);
        // console.log("balances.debt", balances.debt);
        // console.log("normalisedBalances.debt", normalisedBalances.debt);
        // console.log("prices.debt", vars.prices.debt);

        quote.quantity = params.quantity != 0
            ? params.quantity
            : _deriveQuantity(vars, normalisedBalances, params.cashflowCcy, params.cashflow, params.leverage);
        uint256 lendingLiquidity = vars.moneyMarket.lendingLiquidity(vars.instrument.base) - 1;
        quote.quantity = Math.min(quote.quantity, lendingLiquidity);
        if (lendingLiquidity == quote.quantity) {
            // console.log("quantity was capped to liquidity %s", quote.quantity);
        } else {
            // console.log("quantity was not capped");
        }

        if (quote.quantity == 0) revert("No lending liquidity available");

        quote.oracleData = _oracleData(vars, normalisedBalances, quote.quantity.toInt256());

        if (params.cashflowCcy == Currency.Quote) {
            quote.swapCcy = Currency.Quote;
            quote.swapAmount = quote.quantity.mulPrice(quote.price, vars.instrument.baseUnit);

            quote.cashflowUsed = params.leverage != 0
                ? _deriveCashflowInQuote(vars, quote.oracleData, params.leverage, quote.swapCcy, int256(quote.swapAmount))
                : params.cashflow;

            _calculateMinQuoteCashflow(balances, quote, vars);
            _calculateMaxQuoteCashflow(balances, quote, vars);
            _calculateCashflowUsed(quote);

            // When opening, cashflow can't be greater than swapAmount
            if (balances.collateral == 0) quote.cashflowUsed = quote.cashflowUsed.toUint256().min(quote.swapAmount).toInt256();
            // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());

            quote.oracleData.debt = (
                int256(quote.oracleData.debt)
                    + (int256(quote.swapAmount) - quote.cashflowUsed).mulPrice(vars.prices.debt, vars.instrument.quoteUnit)
            ).toUint256();
            vars.flashLoanQuantity = quote.cashflowUsed > 0 ? (int256(quote.swapAmount) + quote.cashflowUsed).abs() : quote.swapAmount;
        }

        if (params.cashflowCcy == Currency.Base) {
            quote.cashflowUsed = params.leverage != 0
                ? _deriveCashflowInBase(vars, quote.oracleData, params.leverage, int256(quote.quantity))
                : params.cashflow;

            _calculateMinBaseCashflow(quote, vars);
            _calculateMaxBaseCashflow(normalisedBalances, quote, vars);
            _calculateCashflowUsed(quote);

            int256 debtDelta = (int256(quote.quantity) - quote.cashflowUsed).mulPrice(vars.prices.collateral, vars.instrument.baseUnit);

            // console.log("debtDelta %s", debtDelta < 0 ? "-" : "", debtDelta.abs());
            quote.oracleData.debt = (int256(quote.oracleData.debt) + debtDelta).toUint256();
            // console.log("quote.oracleData.debt", quote.oracleData.debt);

            if (quote.cashflowUsed <= 0 || quote.quantity >= quote.cashflowUsed.abs()) {
                quote.swapCcy = Currency.Quote;
                quote.swapAmount = debtDelta.abs().divPrice(vars.prices.debt, vars.instrument.quoteUnit);
                vars.flashLoanQuantity = quote.swapAmount;

                uint256 amountReceived = quote.swapAmount.divPrice(quote.price, vars.instrument.baseUnit);
                quote.cashflowUsed = int256(quote.quantity) - int256(amountReceived);
            } else {
                quote.swapCcy = Currency.Base;
                quote.swapAmount = (int256(quote.quantity) - quote.cashflowUsed).abs();
                quote.cashflowUsed = quote.cashflowUsed;
            }
        }

        if (params.cashflowCcy == Currency.None) {
            quote.swapCcy = Currency.Quote;
            quote.swapAmount = quote.quantity.mulPrice(quote.price, vars.instrument.baseUnit);
            quote.oracleData.debt += quote.swapAmount.mulPrice(vars.prices.debt, vars.instrument.quoteUnit);
            vars.flashLoanQuantity = quote.swapAmount;
        }

        if (quote.swapAmount == 0) {
            quote.swapCcy = Currency.None;
            // console.log("quote.swapCcy NONE");
        } else {
            // console.log(
            //     "quote.swapCcy",
            //     (quote.swapCcy == Currency.Base ? vars.instrument.base : vars.instrument.quote).symbol()
            // );
        }

        // console.log("quote.quantity", quote.quantity);
        // console.log("quote.swapAmount", quote.swapAmount);
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        // console.log("quote.price", quote.price);
        // console.log("flashLoanQuantity", vars.flashLoanQuantity);
        // console.log("quote.minCashflow %s%s", quote.minCashflow < 0 ? "-" : "", quote.minCashflow.abs());
        // console.log("quote.maxCashflow %s%s", quote.maxCashflow < 0 ? "-" : "", quote.maxCashflow.abs());

        (quote.flashLoanProvider, quote.transactionFees) = _flashLoanProvider(vars.instrument.quote, vars.flashLoanQuantity);
        // console.log("flashLoanProvider %s fees %s", quote.flashLoanProvider.toString(), quote.transactionFees);

        (quote.fee, quote.feeCcy) = _fee(vars.positionOwner, params.positionId, quote.quantity);
        // console.log("quote.feeCcy", quote.feeCcy.toString());
        // console.log("quote.fee", quote.fee);
    }

    function _oracleData(FU2Deep memory vars, NormalisedBalances memory balances, int256 quantity)
        private
        pure
        returns (
            // pure
            OracleData memory oracleData
        )
    {
        oracleData.unit = vars.prices.unit;
        // Apply slippage to the potential value of the new quantity as collateral
        quantity = quantity > 0 ? quantity * int256(1e4 - vars.slippageTolerance) / 1e4 : quantity;
        // console.log(
        //     "---> quantity in base ccy %s", quantity.mulPrice(vars.prices.collateral, vars.instrument.baseUnit).abs()
        // );
        oracleData.collateral =
            (balances.collateral.toInt256() + quantity.mulPrice(vars.prices.collateral, vars.instrument.baseUnit)).toUint256();
        oracleData.debt = balances.debt;
    }

    function _flashLoanProvider(IERC20 asset, uint256 amount) internal view returns (IERC7399 provider, uint256 minFee) {
        minFee = type(uint256).max;
        for (uint256 i = 0; i < flashLoanProviders.length; i++) {
            IERC7399 p = flashLoanProviders[i];
            uint256 fee = p.flashFee(address(asset), amount);

            if (fee < minFee) {
                minFee = fee;
                provider = p;
            }
            if (minFee == 0) break;
        }

        require(minFee != type(uint256).max, "no flash loan provider");
    }

    /// @inheritdoc IQuoter
    function quoteClose(CloseQuoteParams memory params) external returns (Quote memory quote) {
        // console.log("\nquoteClose");
        FU2Deep memory vars;
        vars.slippageTolerance = params.slippageTolerance;
        vars.positionId = params.positionId;

        (vars.symbol, vars.mm,,) = params.positionId.decode();
        vars.positionOwner = positionNFT.positionOwner(params.positionId);
        vars.instrument = contango.instrument(vars.symbol);

        vars.moneyMarket = moneyMarkets[params.positionId.getMoneyMarket()];
        Balances memory balances = vars.moneyMarket.balances(params.positionId, vars.instrument.base, vars.instrument.quote);
        NormalisedBalances memory normalisedBalances =
            vars.moneyMarket.normalisedBalances(params.positionId, vars.instrument.base, vars.instrument.quote);
        params.quantity = Math.min(balances.collateral, params.quantity);
        quote.fullyClose = params.quantity == balances.collateral;
        // console.log("quote.fullyClose", quote.fullyClose);

        vars.prices = vars.moneyMarket.prices(vars.symbol, vars.instrument.base, vars.instrument.quote);

        // console.log("params.cashflowCcy", params.cashflowCcy.toString());
        // console.log("params.cashflow %s%s", params.cashflow < 0 ? "-" : "", params.cashflow.abs());
        // console.log("params.quantity", params.quantity);
        quote.price = vars.instrument.quoteUnit * vars.prices.collateral / vars.prices.debt;
        // console.log("quote.price", quote.price);
        // console.log("balances.collateral", balances.collateral);
        // console.log("normalisedBalances.collateral", normalisedBalances.collateral);
        // console.log("prices.collateral", vars.prices.collateral);
        // console.log("balances.debt", balances.debt);
        // console.log("normalisedBalances.debt", normalisedBalances.debt);
        // console.log("prices.debt", vars.prices.debt);

        quote.price = quote.price;
        quote.quantity = params.quantity != 0
            ? params.quantity
            : _deriveQuantity(vars, normalisedBalances, params.cashflowCcy, params.cashflow, params.leverage);
        quote.oracleData = _oracleData(vars, normalisedBalances, -quote.quantity.toInt256());

        (quote.fee, quote.feeCcy) = _fee(vars.positionOwner, params.positionId, quote.quantity);

        if (params.cashflowCcy == Currency.Base) {
            quote.swapCcy = Currency.Base;
            if (quote.quantity == balances.collateral) {
                quote.cashflowUsed = int256(balances.debt).divPrice(quote.price, vars.instrument.baseUnit) - int256(quote.quantity);
            } else {
                quote.cashflowUsed = params.leverage > 0
                    ? _deriveCashflowInBase(vars, quote.oracleData, params.leverage, -int256(quote.quantity))
                    : params.cashflow;
            }

            _calculateMinBaseCashflow(quote, vars);
            _calculateMaxBaseCashflow(normalisedBalances, quote, vars);
            _calculateCashflowUsed(quote);

            int256 delta = int256(quote.quantity) + quote.cashflowUsed;
            // console.log("delta %s%s", delta < 0 ? "-" : "", delta.abs());
            if (delta > 0) {
                quote.swapAmount = delta.toUint256();
            } else {
                quote.swapCcy = Currency.Quote;
                quote.swapAmount = (-delta).toUint256().mulPrice(quote.price, vars.instrument.baseUnit);
            }

            if (quote.fullyClose) {
                quote.oracleData.debt = 0;
            } else {
                quote.oracleData.debt = (
                    int256(quote.oracleData.debt)
                        - (delta - int256(quote.feeCcy == Currency.Base ? quote.fee : 0)).mulPrice(
                            vars.prices.collateral, vars.instrument.baseUnit
                        )
                ).toUint256();
            }
            // console.log("quote.oracleData.debt", quote.oracleData.debt);
        } else {
            quote.swapCcy = Currency.Base;
            quote.swapAmount = quote.quantity;

            if (params.leverage > 0) {
                params.cashflow = _deriveCashflowInQuote(vars, quote.oracleData, params.leverage, quote.swapCcy, -int256(quote.swapAmount));
            }

            if (params.cashflow > 0) {
                int256 debtDelta = int256(balances.debt) - int256(quote.swapAmount.mulPrice(quote.price, vars.instrument.baseUnit));

                quote.cashflowUsed = SignedMath.min(params.cashflow, debtDelta);
            } else if (params.cashflow < 0) {
                quote.cashflowUsed = params.cashflow;
            }

            _calculateMinQuoteCashflow(balances, quote, vars);
            _calculateMaxQuoteCashflow(balances, quote, vars);
            _calculateCashflowUsed(quote);

            if (quote.fullyClose) {
                quote.oracleData.debt = 0;
            } else {
                int256 amountReceived = (-int256(quote.quantity) + int256(quote.feeCcy == Currency.Base ? quote.fee : 0)).mulPrice(
                    quote.price, vars.instrument.baseUnit
                );
                int256 debtDelta = (amountReceived - quote.cashflowUsed).mulPrice(vars.prices.debt, vars.instrument.quoteUnit);

                // console.log("amountReceived %s%s", amountReceived < 0 ? "-" : "", amountReceived.abs());
                // console.log("debtDelta %s%s", debtDelta < 0 ? "-" : "", debtDelta.abs());
                quote.oracleData.debt = (int256(quote.oracleData.debt) + debtDelta).toUint256();
            }
            // console.log("quote.oracleData.debt", quote.oracleData.debt);
        }

        if (quote.swapAmount == 0) {
            quote.swapCcy = Currency.None;
            // console.log("quote.swapCcy NONE");
        } else {
            // console.log(
            //     "quote.swapCcy",
            //     (quote.swapCcy == Currency.Base ? vars.instrument.base : vars.instrument.quote).symbol()
            // );

            // console.log("quote.swapAmount", quote.swapAmount);
            quote.swapAmount = quote.fullyClose && params.cashflowCcy == Currency.Base
                ? quote.swapAmount * (1e4 + vars.slippageTolerance * 2) / 1e4
                : quote.swapAmount;
            // console.log("quote.swapAmount", quote.swapAmount);

            if (quote.swapCcy == Currency.Base && (!quote.fullyClose || params.cashflowCcy == Currency.Quote)) {
                // console.log("discounting fee %s from swapAmount %s", quote.swapAmount, quote.fee);
                quote.swapAmount -= quote.fee;
            }
            vars.flashLoanQuantity = quote.swapAmount;
        }

        // console.log("quote.quantity", quote.quantity);
        // console.log("quote.swapAmount", quote.swapAmount);
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        // console.log("quote.price", quote.price);
        // console.log("flashLoanQuantity", vars.flashLoanQuantity);

        if (quote.swapCcy == Currency.Base) {
            (quote.flashLoanProvider, quote.transactionFees) = _flashLoanProvider(vars.instrument.base, vars.flashLoanQuantity);
            // scenario 23 is a special case that only the necessary to repay debt with some fat is swapped, flash loan fees come out of remaining collateral
            if (!(quote.fullyClose && params.cashflowCcy == Currency.Base)) {
                // not 100% correct but approx enough so flash loan fees can be afforded and achieve the desired operation
                quote.swapAmount -= quote.transactionFees;
            }
        }

        // console.log("flashLoanProvider %s fees %s", quote.flashLoanProvider.toString(), quote.transactionFees);
        // console.log("quote.feeCcy", quote.feeCcy.toString());
        // console.log("quote.fee", quote.fee);
    }

    function _fee(address trader, PositionId positionId, uint256 quantity) private view returns (uint256 fee, Currency feeCcy) {
        IFeeModel feeModel = contango.feeManager().feeModel();
        if (address(feeModel) != address(0)) {
            fee = feeModel.calculateFee(trader, positionId, quantity);
            feeCcy = Currency.Base;
        }
    }

    function _calculateMinQuoteCashflow(Balances memory balances, Quote memory quote, FU2Deep memory vars) internal view {
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        // console.log("minCR", vars.moneyMarket.minCR(vars.positionId, vars.instrument.base, vars.instrument.quote));
        uint256 maxDebt =
            quote.oracleData.collateral * 1e18 / vars.moneyMarket.minCR(vars.positionId, vars.instrument.base, vars.instrument.quote);
        // console.log("maxDebt", maxDebt);
        maxDebt =
            Math.min(maxDebt, vars.moneyMarket.borrowingLiquidity(vars.instrument.quote) * vars.prices.debt / vars.instrument.quoteUnit);
        // console.log("maxDebt", maxDebt);
        uint256 maxDebtQuote = maxDebt.divPrice(vars.prices.debt, vars.instrument.quoteUnit);
        // console.log("maxDebtQuote", maxDebtQuote);

        int256 swapAmount = quote.swapCcy == Currency.Base
            ? int256(quote.swapAmount.mulPrice(quote.price, vars.instrument.baseUnit))
            : int256(quote.swapAmount);
        swapAmount = swapAmount * (vars.opening ? int256(1) : -1);

        if (balances.debt < maxDebtQuote) {
            uint256 refinancingRoom = maxDebtQuote - balances.debt;
            quote.minCashflow = swapAmount - int256(refinancingRoom);
        }

        if (balances.debt > maxDebtQuote) {
            uint256 minDebtThatHasToBeBurned = balances.debt - maxDebtQuote;
            quote.minCashflow = int256(minDebtThatHasToBeBurned) + swapAmount;
        }
        // console.log("quote.minCashflow %s%s", quote.minCashflow < 0 ? "-" : "", quote.minCashflow.abs());
    }

    function _calculateMaxQuoteCashflow(Balances memory balances, Quote memory quote, FU2Deep memory vars) internal pure {
        uint256 maxDebtThatCanBeBurned = balances.debt;

        int256 swapAmount = quote.swapCcy == Currency.Base
            ? int256(quote.swapAmount.mulPrice(quote.price, vars.instrument.baseUnit))
            : int256(quote.swapAmount);
        swapAmount = swapAmount * (vars.opening ? int256(1) : -1);

        quote.maxCashflow = int256(maxDebtThatCanBeBurned) + swapAmount;
        // console.log("quote.maxCashflow %s%s", quote.maxCashflow < 0 ? "-" : "", quote.maxCashflow.abs());
    }

    function _calculateMinBaseCashflow(Quote memory quote, FU2Deep memory vars) internal view {
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        // console.log("quote.oracleData.collateral", quote.oracleData.collateral);
        // console.log("quote.oracleData.debt", quote.oracleData.debt);
        uint256 maxDebt = quote.oracleData.collateral * WAD
            / vars.moneyMarket.minCR(vars.positionId, vars.instrument.base, vars.instrument.quote) * 0.999e18 / 1e18;
        // console.log("maxDebt", maxDebt);
        maxDebt = Math.min(
            maxDebt, vars.moneyMarket.borrowingLiquidity(vars.instrument.quote).mulPrice(vars.prices.debt, vars.instrument.quoteUnit)
        );
        // console.log("maxDebt", maxDebt);
        // uint256 maxDebtBase = maxDebt.divPrice(vars.prices.collateral, vars.instrument.baseUnit);
        // console.log("maxDebtBase", maxDebtBase);

        int256 quantity = vars.opening ? int256(quote.quantity) : -int256(quote.quantity);

        if (quote.oracleData.debt < maxDebt) {
            // console.log("-- quote.oracleData.debt < maxDebt --");
            uint256 refinancingRoom = maxDebt - quote.oracleData.debt;
            uint256 refinancingRoomBase = refinancingRoom.divPrice(vars.prices.collateral, vars.instrument.baseUnit);

            // console.log("refinancingRoom", refinancingRoom);
            // console.log("refinancingRoomBase", refinancingRoomBase);

            quote.minCashflow = quantity - int256(refinancingRoomBase);
        }

        if (quote.oracleData.debt > maxDebt) {
            // console.log("-- quote.oracleData.debt > maxDebt --");
            uint256 minDebtThatHasToBeBurned = quote.oracleData.debt - maxDebt;
            uint256 minDebtThatHasToBeBurnedBase = minDebtThatHasToBeBurned.divPrice(vars.prices.collateral, vars.instrument.baseUnit);
            quote.minCashflow = int256(minDebtThatHasToBeBurnedBase) + quantity;
        }

        // console.log("++++++++ quote.minCashflow %s%s", quote.minCashflow < 0 ? "-" : "", quote.minCashflow.abs());
    }

    function _calculateMaxBaseCashflow(NormalisedBalances memory balances, Quote memory quote, FU2Deep memory vars) internal pure {
        int256 quantity = vars.opening ? int256(quote.quantity) : -int256(quote.quantity);
        uint256 maxDebtThatCanBeBurned = balances.debt;
        uint256 maxDebtThatCanBeBurnedBase = maxDebtThatCanBeBurned.divPrice(vars.prices.collateral, vars.instrument.baseUnit);
        quote.maxCashflow = int256(maxDebtThatCanBeBurnedBase) + quantity;
        // console.log("quote.maxCashflow %s%s", quote.maxCashflow < 0 ? "-" : "", quote.maxCashflow.abs());
    }

    function _calculateCashflowUsed(Quote memory quote) internal pure {
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        quote.cashflowUsed = SignedMath.max(quote.cashflowUsed, quote.minCashflow);
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        quote.cashflowUsed = SignedMath.min(quote.cashflowUsed, quote.maxCashflow);
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
    }

    /// @inheritdoc IQuoter
    function quoteModify(ModifyQuoteParams calldata params) external returns (Quote memory quote) {
        FU2Deep memory vars;

        (vars.symbol, vars.mm,,) = params.positionId.decode();
        vars.positionOwner = positionNFT.positionOwner(params.positionId);
        vars.instrument = contango.instrument(vars.symbol);

        vars.moneyMarket = moneyMarkets[params.positionId.getMoneyMarket()];
        Balances memory balances = vars.moneyMarket.balances(params.positionId, vars.instrument.base, vars.instrument.quote);
        vars.prices = vars.moneyMarket.prices(vars.symbol, vars.instrument.base, vars.instrument.quote);
        quote.oracleData.unit = vars.prices.unit;
        quote.oracleData.collateral = balances.collateral * vars.prices.collateral / vars.instrument.baseUnit;
        quote.oracleData.debt = balances.debt * vars.prices.debt / vars.instrument.quoteUnit;

        // console.log("cashflowCcy", params.cashflowCcy.toString());
        quote.price = vars.instrument.quoteUnit * vars.prices.collateral / vars.prices.debt;
        // console.log("quote.price", quote.price);
        // console.log("balances.collateral", balances.collateral);
        // console.log("prices.collateral", vars.prices.collateral);
        // console.log("balances.debt", balances.debt);
        // console.log("prices.debt", vars.prices.debt);

        if (params.leverage > 0) {
            if (params.cashflowCcy == Currency.Base) quote.cashflowUsed = _deriveCashflowInBase(vars, quote.oracleData, params.leverage, 0);
            else quote.cashflowUsed = _deriveCashflowInQuote(vars, quote.oracleData, params.leverage, Currency.None, 0);
        } else {
            quote.cashflowUsed = params.cashflow;
        }

        if (params.cashflowCcy == Currency.Base) {
            if (quote.cashflowUsed > 0) {
                quote.swapCcy = Currency.Base;
                quote.swapAmount = uint256(quote.cashflowUsed);
            } else {
                quote.swapCcy = Currency.Quote;
                quote.swapAmount = quote.cashflowUsed.abs().mulPrice(quote.price, vars.instrument.baseUnit);
            }
        } else {
            // cap cashflow to maxDebt
            quote.cashflowUsed = SignedMath.min(quote.cashflowUsed, int256(balances.debt));
        }

        // console.log("quote.swapAmount", quote.swapAmount);
        // console.log("quote.cashflowUsed %s%s", quote.cashflowUsed < 0 ? "-" : "", quote.cashflowUsed.abs());
        // console.log("quote.price", quote.price);

        (quote.flashLoanProvider, quote.transactionFees) = _flashLoanProvider(vars.instrument.quote, vars.flashLoanQuantity);
    }

    function _deriveCashflowInQuote(
        FU2Deep memory vars,
        OracleData memory oracleData,
        uint256 leverage,
        Currency swapCcy,
        int256 swapAmount
    ) internal pure returns (int256 cashflow) {
        // console.log("leverage", leverage);
        if (swapCcy == Currency.Base) {
            swapAmount =
                swapAmount.mulPrice(vars.prices.collateral, vars.instrument.baseUnit).divPrice(vars.prices.debt, vars.instrument.quoteUnit);
        }
        // console.log("swapAmount %s%s", swapAmount < 0 ? "-" : "", swapAmount.abs());

        uint256 targetDebt = leverage < 1e18 ? 0 : oracleData.collateral - oracleData.collateral.mulDiv(1e18, leverage);
        uint256 debtDelta;

        if (targetDebt >= oracleData.debt) {
            // Debt needs to increase to reach the desired leverage
            debtDelta = targetDebt - oracleData.debt;
            cashflow = -(int256(debtDelta).divPrice(vars.prices.debt, vars.instrument.quoteUnit) - swapAmount);
        } else {
            // Debt needs to be burnt to reach the desired leverage
            debtDelta = oracleData.debt - targetDebt;
            cashflow = int256(debtDelta).divPrice(vars.prices.debt, vars.instrument.quoteUnit) + swapAmount;
        }

        // console.log("targetDebt %s", targetDebt);
        // console.log("oracleData.collateral %s", oracleData.collateral);
        // console.log("oracleData.debt %s", oracleData.debt);
        // console.log("debtDelta %s", debtDelta);
        // console.log("derived cashflow %s%s", cashflow < 0 ? "-" : "", cashflow.abs());
    }

    function _deriveCashflowInBase(FU2Deep memory vars, OracleData memory oracleData, uint256 leverage, int256 quantity)
        internal
        pure
        returns (int256 cashflow)
    {
        // console.log("leverage", leverage);

        uint256 targetDebt = leverage < 1e18 ? 0 : oracleData.collateral - oracleData.collateral.mulDiv(1e18, leverage);

        int256 debtDelta;
        if (targetDebt > oracleData.debt) {
            // Debt needs to increase to reach the desired leverage
            debtDelta = (targetDebt - oracleData.debt).toInt256();
        } else {
            // Debt needs to be burnt to reach the desired leverage
            debtDelta = -(oracleData.debt - targetDebt).toInt256();
        }

        // trim off precision excess, otherwise baseDebtDelta could be off due to base and oracle price being more precise than quote
        if (vars.instrument.quoteUnit < oracleData.unit) {
            int256 deltaUnit = int256(oracleData.unit / vars.instrument.quoteUnit);
            debtDelta = (debtDelta / deltaUnit) * deltaUnit;
        }

        // console.log("targetDebt %s", targetDebt);
        // console.log("debtDelta %s%s", debtDelta < 0 ? "-" : "", debtDelta.abs());
        // console.log("oracleData.collateral %s", oracleData.collateral);
        // console.log("oracleData.debt %s", oracleData.debt);

        int256 baseDebtDelta = debtDelta.divPrice(vars.prices.collateral, vars.instrument.baseUnit);
        // console.log("baseDebtDelta %s%s", baseDebtDelta < 0 ? "-" : "", baseDebtDelta.abs());

        cashflow = quantity - baseDebtDelta;
        // console.log("derived cashflow %s%s", cashflow < 0 ? "-" : "", cashflow.abs());
    }

    // https://www.wolframalpha.com/input?i=1%2F%281-%28%286000%2Bx%29%2F%2810000%2Bx%29%29%29%3D3.5
    // https://www.wolframalpha.com/input?i=%28x+%2B+10000%29%2F4000+%3D+3.5
    // (x + 10000)/4000 = 3.5
    // 3.5 * 4000 - 10000 = 4000
    function _deriveQuantity(
        FU2Deep memory vars,
        NormalisedBalances memory balances,
        Currency cashflowCcy,
        int256 cashflow,
        uint256 leverage
    ) internal pure returns (uint256 quantity) {
        int256 normalisedCashflow = cashflowCcy == Currency.Base
            ? cashflow.mulPrice(vars.prices.collateral, vars.instrument.baseUnit)
            : cashflow.mulPrice(vars.prices.debt, vars.instrument.quoteUnit);

        uint256 normalisedCollateral = (balances.collateral.toInt256() + normalisedCashflow).toUint256();

        // console.log("normalisedCashflow", normalisedCollateral);
        // console.log("normalisedCollateral", normalisedCollateral);

        int256 debtDelta = leverage.mulDiv(normalisedCollateral - balances.debt, WAD).toInt256() - normalisedCollateral.toInt256();
        // console.log("debtDelta %s%s", debtDelta < 0 ? "-" : "", debtDelta.abs());

        quantity = cashflowCcy == Currency.Base
            ? (cashflow + debtDelta.divPrice(vars.prices.collateral, vars.instrument.baseUnit)).abs()
            : (debtDelta + normalisedCashflow).divPrice(vars.prices.collateral, vars.instrument.baseUnit).abs();

        // console.log("derived quantity", quantity);
    }

}

library QuoterHelper {

    using Math for *;

    function mulPrice(uint256 amount, uint256 price, uint256 unit) internal pure returns (uint256) {
        return amount.mulDiv(price, unit);
    }

    function mulPrice(int256 amount, uint256 price, uint256 unit) internal pure returns (int256) {
        return amount * int256(price) / int256(unit);
    }

    function divPrice(uint256 amount, uint256 price, uint256 unit) internal pure returns (uint256) {
        return amount.mulDiv(unit, price);
    }

    function divPrice(int256 amount, uint256 price, uint256 unit) internal pure returns (int256) {
        return amount * int256(unit) / int256(price);
    }

}

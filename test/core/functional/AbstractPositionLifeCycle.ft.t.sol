//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

/// @dev scenario implementation for https://docs.google.com/spreadsheets/d/1uLRNJOn3uy2PR5H2QJ-X8unBRVCu1Ra51ojMjylPH90/edit#gid=0
abstract contract AbstractPositionLifeCycleFunctional is BaseTest {

    using Math for *;
    using SignedMath for *;

    enum Action {
        Open,
        Close,
        Modify
    }

    struct Inputs {
        uint256 quantity;
        int256 cashflow;
        Currency cashflowCcy;
    }

    struct Expectations {
        uint256 collateral;
        uint256 debt;
        uint256 flashLoanAmount;
        uint256 price;
        Currency swapInputCcy;
        uint256 swapInput;
        uint256 swapOutput;
        uint256 quantity;
        uint256 fee;
        Currency feeCcy;
        uint256 estimatedFee;
        uint256 estimatedFeeInQuote;
        int256 tradeCashflow;
    }

    // effective when opening because the fee is included in final quantity to compensate for the intended quantity passed
    // deriveQuoteValues.ts::calculateTradingFee()
    uint256 internal constant QUOTER_FEE_ON_OPEN = 1e36 / (1e18 - DEFAULT_TRADING_FEE) - 1e18;
    uint256 internal constant ADJUSTED_QUOTER_FEE = DEFAULT_TRADING_FEE + 0.00001e18;
    uint256 internal constant ADJUSTED_QUOTER_FEE_ON_OPEN = 1e36 / (1e18 - ADJUSTED_QUOTER_FEE) - 1e18;

    // 0.00100001% to include dust from flash loan fees, without them 0.0001% should suffice
    uint256 internal constant CONTANGO_BASE_DUST_TOLERANCE = 0.0000100001e18;

    uint256 internal constant MULTIPLIER_UNIT = 1e18;
    uint256 internal constant WETH_STABLE_MULTIPLIER = 0.001e18; // 0.001e18: 1 base = 0.001 quote
    uint256 internal constant STABLE_WETH_MULTIPLIER = 1000e18; // 1000e18: 1000 base = 1 quote

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    Contango internal contango;
    IVault internal vault;

    Inputs internal inputs;
    Expectations internal expectations;

    uint256 internal price;
    uint256 internal spread;
    uint256 internal multiplier;

    function setUp(Network network, MoneyMarketId _mm, bytes32 base, bytes32 quote, uint256 _multiplier) internal virtual {
        setUp(network, forkBlock(network), _mm, base, quote, _multiplier);
    }

    function setUp(Network network, uint256 blockNo, MoneyMarketId _mm, bytes32 base, bytes32 quote, uint256 _multiplier)
        internal
        virtual
    {
        env = provider(network);
        env.init(blockNo);
        contango = env.contango();
        vault = env.vault();

        mm = _mm;
        instrument = env.createInstrument({ baseData: env.erc20(base), quoteData: env.erc20(quote) });

        multiplier = _multiplier;
        price = (1 * instrument.quoteUnit).mulDiv(MULTIPLIER_UNIT, multiplier);
        spread = price / 1000;

        // go around rounding issues when calculating price from swap data
        env.positionActions().setSlippageTolerance(DEFAULT_SLIPPAGE_TOLERANCE + 1);

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: int256(multiplier > MULTIPLIER_UNIT ? DEFAULT_ORACLE_UNIT : DEFAULT_ORACLE_UNIT.mulDiv(MULTIPLIER_UNIT, multiplier)),
            quoteUsdPrice: int256(multiplier < MULTIPLIER_UNIT ? DEFAULT_ORACLE_UNIT : DEFAULT_ORACLE_UNIT.mulDiv(multiplier, MULTIPLIER_UNIT)),
            uniswapFee: 500
        });

        poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(int256(spread));

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
    }

    // Borrow 6k, Sell 6k for ~6 ETH
    function testScenario01() public {
        inputs.quantity = _adjustedBase(10);
        inputs.cashflow = _adjustedBaseI(4);
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(6000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = uint256(inputs.cashflow) + expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (TSQuote memory quote, PositionId positionId, Trade memory trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = discountFee(expectations.quantity);
        expectations.debt = expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Borrow 6k, Sell 10k for ~10 ETH
    function testScenario02() public {
        inputs.quantity = _adjustedBase(10);
        inputs.cashflow = _adjustedQuoteI(4000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(6000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = uint256(inputs.cashflow) + expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (TSQuote memory quote, PositionId positionId, Trade memory trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = discountFee(expectations.swapOutput);
        expectations.debt = expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Borrow 4k, Sell 4k for ~4 ETH
    function testScenario03() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = 0;
        inputs.cashflowCcy = Currency.None;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(4000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            leverage: 0,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH
    function testScenario04() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedBaseI(3);
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(1000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = uint256(inputs.cashflow) + expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Just lend 4 ETH, no spot trade needed
    function testScenario05() public virtual {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedBaseI(4);
        inputs.cashflowCcy = Currency.Base;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN, Math.Rounding.Up);
        expectations.quantity = inputs.quantity + expectations.estimatedFee;

        // bump cashflow to cover the fee and ensure no spot trade
        inputs.cashflow += int256(expectations.estimatedFee);
        expectations.tradeCashflow = inputs.cashflow;

        expectations.price = 0; // No swap happened, the graph will pull the price from the oracle
        expectations.swapInputCcy = Currency.None;
        expectations.swapInput = 0;
        expectations.swapOutput = 0;
        expectations.fee = tradingFee(inputs.quantity, QUOTER_FEE_ON_OPEN);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Lend 4 ETH & Sell 2 ETH, repay debt with the proceeds
    function testScenario06() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedBaseI(6);
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.quantity = inputs.quantity + expectations.estimatedFee;
        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = uint256(inputs.cashflow) - expectations.quantity;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(inputs.quantity, QUOTER_FEE_ON_OPEN);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt - expectations.swapOutput;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 2 ETH for ~2k, repay debt with the proceeds
    function testScenario07() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = 0;
        inputs.cashflow = _adjustedBaseI(2);
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.fee = 0;
        expectations.feeCcy = Currency.None;
        expectations.quantity = inputs.quantity;
        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = uint256(inputs.cashflow);
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);

        expectations.collateral = balances.collateral;
        expectations.debt = balances.debt - expectations.swapOutput;

        (quote, trade) =
            env.positionActions().modifyPosition({ positionId: positionId, cashflow: inputs.cashflow, cashflowCcy: inputs.cashflowCcy });

        _assertPosition(positionId, trade, Action.Modify);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH but only borrow what the trader's not paying for (borrow 1k)
    function testScenario08() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(3000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(1000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = uint256(inputs.cashflow) + expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, no changes on debt
    function testScenario09() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(4000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        // bump cashflow to cover the fee and ensure no extra debt
        inputs.cashflow += int256(expectations.estimatedFeeInQuote);
        expectations.tradeCashflow = inputs.cashflow;

        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = uint256(inputs.cashflow);
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH & repay debt with 2k excess cashflow
    function testScenario10() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(6000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.fee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.feeCcy = Currency.Base;
        expectations.quantity = inputs.quantity + expectations.fee;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        // uses mark price since that's what we pass to the quoter
        expectations.swapInput = expectations.quantity.mulDiv(price, instrument.baseUnit);
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        // update quantity and fee to reflect the actual swap
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt - uint256(inputs.cashflow) + expectations.swapInput;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Repay debt with cashflow
    function testScenario11() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = 0;
        inputs.cashflow = _adjustedQuoteI(2000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        // no position quantity change
        // no swap
        expectations.quantity = 0;
        expectations.fee = 0;
        expectations.feeCcy = Currency.None;
        expectations.price = 0;
        expectations.swapInputCcy = Currency.None;
        expectations.swapInput = 0;
        expectations.swapOutput = 0;

        expectations.collateral = balances.collateral;
        expectations.debt = balances.debt - uint256(inputs.cashflow);

        (quote, trade) =
            env.positionActions().modifyPosition({ positionId: positionId, cashflow: inputs.cashflow, cashflowCcy: inputs.cashflowCcy });

        _assertPosition(positionId, trade, Action.Modify);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4.1k for ~4.1 ETH, Withdraw 0.1, Lend ~4 (take 4.1k new debt)
    function testScenario12() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = -int256(0.1e1 * (10 ** (instrument.baseDecimals - 1)));
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.price = price + spread;
        // uses mark price since that's what we pass to the quoter
        expectations.flashLoanAmount =
            (inputs.quantity + inputs.cashflow.abs()).mulDiv(price, instrument.baseUnit) + expectations.estimatedFeeInQuote;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput - inputs.cashflow.abs();
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), inputs.cashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 2.1k for ~2.1 ETH, Withdraw 1.1, Lend ~1 (take 2.1k new debt)
    function testScenario13() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(1);
        inputs.cashflow = -int256(1.1e1 * (10 ** (instrument.baseDecimals - 1)));
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.price = price + spread;
        // uses mark price since that's what we pass to the quoter
        expectations.flashLoanAmount =
            (inputs.quantity + inputs.cashflow.abs()).mulDiv(price, instrument.baseUnit) + expectations.estimatedFeeInQuote;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput - inputs.cashflow.abs();
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), inputs.cashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, Withdraw 100 (take 4.1k new debt)
    function testScenario14() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(-100);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.price = price + spread;
        // uses mark price since that's what we pass to the quoter
        expectations.flashLoanAmount =
            inputs.quantity.mulDiv(price, instrument.baseUnit) + inputs.cashflow.abs() + expectations.estimatedFeeInQuote;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount - inputs.cashflow.abs();
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), inputs.cashflow.abs(), "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH, Withdraw 1.1k (take 2.1k new debt)
    function testScenario15() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(1);
        inputs.cashflow = _adjustedQuoteI(-1100);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.price = price + spread;
        // uses mark price since that's what we pass to the quoter
        expectations.flashLoanAmount =
            inputs.quantity.mulDiv(price, instrument.baseUnit) + inputs.cashflow.abs() + expectations.estimatedFeeInQuote;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount - inputs.cashflow.abs();
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), inputs.cashflow.abs(), "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay debt with proceeds
    function testScenario16() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = 0;
        inputs.cashflowCcy = Currency.None;

        expectations.tradeCashflow = inputs.cashflow;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Sell 5 ETH for ~5k, repay debt with proceeds
    function testScenario17() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedBaseI(1);
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity + uint256(inputs.cashflow) - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Sell 4 ETH for ~4k, repay debt worth ~5k
    function testScenario18() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(1000);
        inputs.cashflowCcy = Currency.Quote;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput - uint256(inputs.cashflow);

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Sell 2.5 ETH for ~2.5k, withdraw 1.5 ETH, repay ~2.5k
    function testScenario19() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = -int256(1.5e1 * (10 ** (instrument.baseDecimals - 1)));
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - inputs.cashflow.abs() - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.tradeCashflow -= int256(expectations.estimatedFee - expectations.fee);

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Borrow 200, Sell 200 for ~0.2 ETH, withdraw ~1.2 ETH
    function testScenario20() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(1);
        inputs.cashflow = _adjustedBaseI(-1.2e1) / int256(1e1);
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        // uses mark price since that's what we pass to the quoter
        expectations.swapInput =
            (inputs.cashflow.abs() - expectations.quantity + expectations.estimatedFee).mulDiv(price, instrument.baseUnit);
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt + expectations.swapInput;

        // cashflow is approx and depends on swap
        expectations.tradeCashflow = -int256(expectations.quantity - expectations.fee + expectations.swapOutput);

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~2.5k debt, withdraw 1.5k
    function testScenario21() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(-1500);
        inputs.cashflowCcy = Currency.Quote;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput + inputs.cashflow.abs();

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), inputs.cashflow.abs(), "trader quote balance");

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Sell 1 ETH for ~1k, take ~200 debt, withdraw 1.2k
    function testScenario22() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(1);
        inputs.cashflow = _adjustedQuoteI(-1200);
        inputs.cashflowCcy = Currency.Quote;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput + inputs.cashflow.abs();

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), inputs.cashflow.abs(), "trader quote balance");

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Sell 6 ETH for ~6k, repay ~6k, withdraw 4 ETH
    function testScenario23() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = type(uint128).max;
        inputs.cashflow = 0;
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.quantity = balances.collateral;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        // overshoots debt by 2x slippage
        uint256 currentSlippage = env.positionActions().slippageTolerance();
        uint256 debtInBase = balances.debt.mulDiv(instrument.baseUnit, price);
        uint256 swapAmountSlippage = slippage(debtInBase, currentSlippage) * 2e4 / 1e4;
        // TODO approximation and leaves dust on contango when flash loan is paid, review with quoter sdk impl
        expectations.flashLoanAmount = debtInBase + swapAmountSlippage;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);

        expectations.tradeCashflow = -int256(expectations.quantity - expectations.swapInput - expectations.fee - quote.transactionFees);

        expectations.collateral = 0;
        expectations.debt = 0;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        // TODO where's the leftover quote?
        assertEqDecimal(instrument.quote.balanceOf(TRADER), 0, instrument.quoteDecimals, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 10 ETH for ~10k, repay 6k, withdraw ~4k
    function testScenario24() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = type(uint128).max;
        inputs.cashflow = 0;
        inputs.cashflowCcy = Currency.Quote;

        env.positionActions().setTestName(
            string.concat("testScenario24 MM=", vm.toString(MoneyMarketId.unwrap(mm)), " Chain=", currentNetwork().toString())
        );

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.quantity = balances.collateral;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.tradeCashflow = -int256(expectations.swapOutput - balances.debt);

        expectations.collateral = 0;
        expectations.debt = 0;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader quote balance");

        env.checkInvariants(
            instrument,
            positionId,
            quote.execParams.flashLoanProvider,
            expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD) + (expectations.estimatedFee - expectations.fee)
        );
    }

    // Borrow 1k, Sell 1k for ~1 ETH, withdraw ~1 ETH
    function testScenario25() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = 0;
        inputs.cashflow = _adjustedBaseI(-1);
        inputs.cashflowCcy = Currency.Base;

        expectations.fee = 0;
        expectations.feeCcy = Currency.None;
        expectations.quantity = inputs.quantity;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        // uses mark price since that's what we pass to the quoter
        expectations.swapInput = inputs.cashflow.abs().mulDiv(price, instrument.baseUnit);
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);

        expectations.tradeCashflow = -int256(expectations.swapOutput);

        expectations.collateral = balances.collateral;
        expectations.debt = balances.debt + expectations.swapOutput;

        (quote, trade) =
            env.positionActions().modifyPosition({ positionId: positionId, cashflow: inputs.cashflow, cashflowCcy: inputs.cashflowCcy });

        expectations.collateral = balances.collateral;
        expectations.debt = balances.debt + expectations.swapInput;

        _assertPosition(positionId, trade, Action.Modify);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Borrow 1k, withdraw 1k
    function testScenario26() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = 0;
        inputs.cashflow = _adjustedQuoteI(-1000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        // no position quantity change
        // no swap
        expectations.quantity = 0;
        expectations.fee = 0;
        expectations.feeCcy = Currency.None;
        expectations.price = 0;
        expectations.swapInputCcy = Currency.None;
        expectations.swapInput = 0;
        expectations.swapOutput = 0;

        expectations.collateral = balances.collateral;
        expectations.debt = balances.debt + inputs.cashflow.abs();

        (quote, trade) =
            env.positionActions().modifyPosition({ positionId: positionId, cashflow: inputs.cashflow, cashflowCcy: inputs.cashflowCcy });

        _assertPosition(positionId, trade, Action.Modify);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Just withdraw 1 ETH, no spot trade needed
    function testScenario27() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(1);
        inputs.cashflow = _adjustedBaseI(-1);
        inputs.cashflowCcy = Currency.Base;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        // discount fee from cashflow to ensure no borrow + spot trade
        inputs.cashflow += int256(expectations.estimatedFee);
        expectations.tradeCashflow = inputs.cashflow;

        expectations.price = 0; // No swap happened, the graph will pull the price from the oracle
        expectations.swapInputCcy = Currency.None;
        expectations.swapInput = 0;
        expectations.swapOutput = 0;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.tradeCashflow -= int256(expectations.estimatedFee - expectations.fee);

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH
    function testScenario28() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(5);
        inputs.cashflow = _adjustedBaseI(1);
        inputs.cashflowCcy = Currency.Base;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(4000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = uint256(inputs.cashflow) + expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 5k for ~5 ETH but only borrow what the trader's not paying for (borrow 4k)
    function testScenario29() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        inputs.quantity = _adjustedBase(5);
        inputs.cashflow = _adjustedQuoteI(1000);
        inputs.cashflowCcy = Currency.Quote;

        expectations.tradeCashflow = inputs.cashflow;

        expectations.estimatedFee = tradingFee(inputs.quantity, ADJUSTED_QUOTER_FEE_ON_OPEN);
        expectations.estimatedFeeInQuote = expectations.estimatedFee.mulDiv(price, instrument.baseUnit);

        expectations.flashLoanAmount = _adjustedQuote(4000) + expectations.estimatedFeeInQuote;
        expectations.price = price + spread;
        expectations.swapInputCcy = Currency.Quote;
        expectations.swapInput = uint256(inputs.cashflow) + expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(instrument.baseUnit, expectations.price);
        expectations.quantity = expectations.swapOutput;
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.collateral = balances.collateral + discountFee(expectations.quantity);
        expectations.debt = balances.debt + expectations.flashLoanAmount + quote.transactionFees;

        _assertPosition(positionId, trade, Action.Open);
        _assertTreasuryBalance(expectations.fee);

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 3 ETH for ~3k, withdraw 1 ETH, repay ~3k
    function testScenario30() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedBaseI(-1);
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - inputs.cashflow.abs() - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.tradeCashflow -= int256(expectations.estimatedFee - expectations.fee);

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~3k debt, withdraw 1k
    function testScenario31() public {
        (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances) = _initialPosition();

        skip(1 seconds);
        balances = env.contangoLens().balances(positionId);

        inputs.quantity = _adjustedBase(4);
        inputs.cashflow = _adjustedQuoteI(-1000);
        inputs.cashflowCcy = Currency.Quote;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.tradeCashflow = inputs.cashflow;

        expectations.quantity = inputs.quantity;
        expectations.estimatedFee = tradingFee(expectations.quantity, ADJUSTED_QUOTER_FEE);

        expectations.flashLoanAmount = expectations.quantity - expectations.estimatedFee - quote.transactionFees;

        expectations.price = price - spread;
        expectations.swapInputCcy = Currency.Base;
        expectations.swapInput = expectations.flashLoanAmount;
        expectations.swapOutput = expectations.swapInput.mulDiv(expectations.price, instrument.baseUnit);
        expectations.fee = tradingFee(expectations.quantity);
        expectations.feeCcy = Currency.Base;

        expectations.collateral = balances.collateral - expectations.quantity;
        expectations.debt = balances.debt - expectations.swapOutput + inputs.cashflow.abs();

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), inputs.cashflow.abs(), "trader quote balance");

        env.checkInvariants(
            instrument, positionId, quote.execParams.flashLoanProvider, expectations.quantity.mulDiv(CONTANGO_BASE_DUST_TOLERANCE, WAD)
        );
    }

    // Close 1x position
    function testScenario32() public {
        FixedFeeModel feeModel = FixedFeeModel(address(contango.feeManager().feeModel()));
        uint256 prevFee = feeModel.defaultFee();
        vm.prank(TIMELOCK_ADDRESS);
        feeModel.setDefaultFee(NO_FEE);

        (TSQuote memory quote, PositionId positionId, Trade memory trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: _adjustedBase(10),
            cashflow: _adjustedBaseI(10),
            cashflowCcy: Currency.Base
        });

        vm.prank(TIMELOCK_ADDRESS);
        feeModel.setDefaultFee(prevFee);

        skip(1 seconds);
        Balances memory balances = env.contangoLens().balances(positionId);

        inputs.quantity = type(uint128).max;
        inputs.cashflow = -1;
        inputs.cashflowCcy = Currency.Base;

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: inputs.quantity,
            cashflow: inputs.cashflow,
            cashflowCcy: inputs.cashflowCcy
        });

        expectations.quantity = balances.collateral;
        expectations.estimatedFee = tradingFee(expectations.quantity, DEFAULT_TRADING_FEE);
        expectations.feeCcy = Currency.Base;
        expectations.fee = expectations.estimatedFee;
        expectations.tradeCashflow = -int256(expectations.quantity) + int256(expectations.fee);

        expectations.flashLoanAmount = 0;

        expectations.price = 0;
        expectations.swapInputCcy = Currency.None;
        expectations.swapInput = 0;
        expectations.swapOutput = 0;

        expectations.collateral = 0;
        expectations.debt = 0;

        _assertPosition(positionId, trade, Action.Close);
        _assertTreasuryBalance(expectations.fee);

        _assertEqBase(instrument.base.balanceOf(TRADER), expectations.tradeCashflow.abs(), "trader base balance");
        assertEqDecimal(instrument.quote.balanceOf(TRADER), 0, instrument.quoteDecimals, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.execParams.flashLoanProvider);
    }

    // ============================ HELPERS ============================

    function _initialPosition()
        private
        returns (TSQuote memory quote, PositionId positionId, Trade memory trade, Balances memory balances)
    {
        int256 previousSpread = poolStub.absoluteSpread();
        poolStub.setAbsoluteSpread(0);

        FixedFeeModel feeModel = FixedFeeModel(address(contango.feeManager().feeModel()));
        uint256 prevFee = feeModel.defaultFee();
        vm.prank(TIMELOCK_ADDRESS);
        feeModel.setDefaultFee(NO_FEE);

        (quote, positionId, trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: _adjustedBase(10),
            cashflow: _adjustedQuoteI(4000),
            cashflowCcy: Currency.Quote
        });

        poolStub.setAbsoluteSpread(previousSpread);

        vm.prank(TIMELOCK_ADDRESS);
        feeModel.setDefaultFee(prevFee);

        balances = env.contangoLens().balances(positionId);
    }

    function _assertPosition(PositionId positionId, Trade memory trade, Action action) private {
        int256 quantity = 0;
        if (action == Action.Open) quantity = int256(discountFee(expectations.quantity));
        if (action == Action.Close) quantity = -int256(expectations.quantity);

        Trade memory expectedTrade = Trade({
            quantity: quantity,
            forwardPrice: expectations.price,
            swap: SwapInfo({
                price: expectations.price,
                inputCcy: expectations.swapInputCcy,
                input: -int256(expectations.swapInput),
                output: int256(expectations.swapOutput)
            }),
            cashflow: expectations.tradeCashflow,
            cashflowCcy: inputs.cashflowCcy,
            fee: expectations.fee,
            feeCcy: expectations.feeCcy
        });

        _assertEqBase(trade.quantity, expectedTrade.quantity, "trade.quantity");
        _assertEqQuote(trade.swap.price, expectedTrade.swap.price, "trade.swap.price");

        assertEq(toString(trade.feeCcy), toString(expectedTrade.feeCcy), "trade.feeCcy");
        require(trade.feeCcy != Currency.Quote, "should not charge fees in quote");
        if (trade.feeCcy == Currency.Base) _assertEqBase(trade.fee, expectedTrade.fee, "trade.fee");

        assertEq(toString(trade.swap.inputCcy), toString(expectedTrade.swap.inputCcy), "trade.swap.inputCcy");
        if (trade.swap.inputCcy == Currency.Base) {
            _assertEqBase(trade.swap.input, expectedTrade.swap.input, "trade.swap.input");
            _assertEqQuote(trade.swap.output, expectedTrade.swap.output, "trade.swap.output");
        } else if (trade.swap.inputCcy == Currency.Quote) {
            _assertEqQuote(trade.swap.input, expectedTrade.swap.input, "trade.swap.input");
            _assertEqBase(trade.swap.output, expectedTrade.swap.output, "trade.swap.output");
        } else {
            assertEq(trade.swap.input, expectedTrade.swap.input, "trade.swap.input");
            assertEq(trade.swap.output, expectedTrade.swap.output, "trade.swap.output");
        }

        assertEq(toString(trade.cashflowCcy), toString(expectedTrade.cashflowCcy), "trade.cashflowCcy");
        if (trade.cashflowCcy == Currency.Base) _assertEqBase(trade.cashflow, expectedTrade.cashflow, "trade.cashflow");
        else if (trade.cashflowCcy == Currency.Quote) _assertEqQuote(trade.cashflow, expectedTrade.cashflow, "trade.cashflow");
        else assertEq(trade.cashflow, expectedTrade.cashflow, "trade.cashflow");

        Balances memory balances = env.contangoLens().balances(positionId);
        _assertEqBase(balances.collateral, expectations.collateral, "collateral");
        _assertEqQuote(balances.debt, expectations.debt, "debt");

        if (balances.collateral > env.bounds(instrument.baseData.symbol).dust) {
            assertTrue(contango.positionNFT().exists(positionId), "positionNFT.exists");
        }
    }

    function _assertTreasuryBalance(uint256 _totalFee) private view {
        uint256 protocolFee;

        if (address(env.feeManager().referralManager()) != address(0)) {
            protocolFee = env.feeManager().referralManager().calculateRewardDistribution(TRADER, _totalFee).protocol;
        }
        _assertEqBase(vault.balanceOf(instrument.base, TREASURY), protocolFee, "treasury vault base balance");
    }

    function _assertEqBase(int256 left, int256 right, string memory message) private view {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, message);
    }

    function _assertEqBase(uint256 left, uint256 right, string memory message) private view {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, message);
    }

    function _assertEqQuote(int256 left, int256 right, string memory message) private view {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.quoteData.symbol).dust, instrument.quoteDecimals, message);
    }

    function _assertEqQuote(uint256 left, uint256 right, string memory message) private view {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.quoteData.symbol).dust, instrument.quoteDecimals, message);
    }

    function _adjustedBaseI(int256 value) private view returns (int256) {
        int256 base = value * int256(instrument.baseUnit);
        return multiplier < MULTIPLIER_UNIT ? base : base * int256(multiplier) / int256(MULTIPLIER_UNIT);
    }

    function _adjustedBase(uint256 value) private view returns (uint256) {
        uint256 base = value * instrument.baseUnit;
        return multiplier < MULTIPLIER_UNIT ? base : base.mulDiv(multiplier, MULTIPLIER_UNIT);
    }

    function _adjustedQuoteI(int256 value) private view returns (int256) {
        int256 quote = value * int256(instrument.quoteUnit);
        return multiplier < MULTIPLIER_UNIT ? quote : quote * int256(MULTIPLIER_UNIT) / int256(multiplier);
    }

    function _adjustedQuote(uint256 value) private view returns (uint256) {
        uint256 quote = value * instrument.quoteUnit;
        return multiplier < MULTIPLIER_UNIT ? quote : quote.mulDiv(MULTIPLIER_UNIT, multiplier);
    }

}

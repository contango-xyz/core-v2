//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

/// @dev scenario implementation for https://docs.google.com/spreadsheets/d/1uLRNJOn3uy2PR5H2QJ-X8unBRVCu1Ra51ojMjylPH90/edit#gid=0
abstract contract AbstractPositionLifeCycleFunctional is BaseTest {

    using Math for *;
    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarket internal mm;
    UniswapPoolStub internal poolStub;
    Contango internal contango;
    IVault internal vault;

    Trade internal expectedTrade;
    uint256 internal expectedCollateral;
    uint256 internal expectedDebt;

    function setUp(Network network, MoneyMarket _mm) internal virtual {
        env = provider(network);
        env.init();
        contango = env.contango();
        vault = env.vault();

        env.positionActions().setSlippageTolerance(0);

        mm = _mm;
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 3000
        });

        poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(1e6);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
    }

    // Borrow 6k, Sell 6k for ~6 ETH
    function testScenario01() public {
        (Quote memory quote, PositionId positionId, Trade memory trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        expectedCollateral = discountFee(10 ether - slippage(6 ether));
        expectedDebt = 6000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 6000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(10 ether - slippage(6 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -6000e6, output: int256(discountSlippage(6 ether)) }),
            cashflow: 4 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(10 ether - slippage(6 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 6000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(10 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(10 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 6k, Sell 10k for ~10 ETH
    function testScenario02() public {
        (Quote memory quote, PositionId positionId, Trade memory trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        expectedCollateral = discountFee(discountSlippage(10 ether));
        expectedDebt = 6000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 6000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(10 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -10_000e6, output: int256(discountSlippage(10 ether)) }),
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(10 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 10_000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(10 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(10 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 4k, Sell 4k for ~4 ETH
    function testScenario03() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 4 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.None
        });

        expectedCollateral = status.collateral + discountFee(discountSlippage(4 ether));
        expectedDebt = status.debt + 4000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 4000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: 0,
            cashflowCcy: Currency.None,
            fee: totalFee(discountSlippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH
    function testScenario04() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 3 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral + discountFee(4 ether - slippage(1 ether));
        expectedDebt = status.debt + 1000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 1000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(4 ether - slippage(1 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -1000e6, output: int256(discountSlippage(1 ether)) }),
            cashflow: 3 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether - slippage(1 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 1000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    function _assertQuoteForScenario4(Quote memory quote) private { }

    // Just lend 4 ETH, no spot trade needed
    function testScenario05() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 4 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral + discountFee(4 ether);
        expectedDebt = status.debt;

        expectedTrade = Trade({
            quantity: int256(discountFee(4 ether)),
            forwardPrice: 0, // No swap happened, the graph will pull the price from the oracle
            swap: SwapInfo({ price: 0, inputCcy: Currency.None, input: 0, output: 0 }),
            cashflow: 4 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);
        assertEq(toString(quote.swapCcy), toString(Currency.None), "quote.swapCcy");
        assertEq(quote.swapAmount, 0, "quote.swapAmount");

        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");
        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Lend 4 ETH & Sell 2 ETH, repay debt with the proceeds
    function testScenario06() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 6 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral + discountFee(4 ether);
        expectedDebt = status.debt - discountSlippage(2000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(4 ether)),
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -2 ether,
                output: int256(discountSlippage(2000e6))
            }),
            cashflow: 6 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, 2 ether, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 2 ETH for ~2k, repay debt with the proceeds
    function testScenario07() public {
        (Quote memory quote, PositionId positionId,, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote) = env.positionActions().modifyPosition({ positionId: positionId, cashflow: 2 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral;
        expectedDebt = status.debt - discountSlippage(2000e6);

        Trade memory emptyTrade;
        _assertPosition(positionId, emptyTrade);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH but only borrow what the trader's not paying for (borrow 1k)
    function testScenario08() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 3000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral + discountFee(discountSlippage(4 ether));
        expectedDebt = status.debt + 1000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 1000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: 3000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, no changes on debt
    function testScenario09() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 4000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral + discountFee(discountSlippage(4 ether));
        expectedDebt = status.debt;

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH & repay debt with 2k excess cashflow
    function testScenario10() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: 6000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral + discountFee(discountSlippage(4 ether));
        expectedDebt = status.debt - 2000e6;

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: 6000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Repay debt with cashflow
    function testScenario11() public {
        (Quote memory quote, PositionId positionId,, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote) = env.positionActions().modifyPosition({ positionId: positionId, cashflow: 2000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral;
        expectedDebt = status.debt - 2000e6;

        Trade memory emptyTrade;
        _assertPosition(positionId, emptyTrade);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4.1k for ~4.1 ETH, Withdraw 1, Lend ~4 (take 4.1k new debt)
    function testScenario12() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -0.1 ether,
            cashflowCcy: Currency.Base
        });

        expectedCollateral = status.collateral + discountFee(4 ether - slippage(4.1 ether));
        expectedDebt = status.debt + 4100e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 4100e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(4 ether - slippage(4.1 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4100e6, output: int256(discountSlippage(4.1 ether)) }),
            cashflow: -0.1 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether - slippage(4.1 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4100e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0.1 ether, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 2.2k for ~2.2 ETH, Withdraw 1.2, Lend ~1 (take 2.2k new debt)
    function testScenario13() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -1.2 ether,
            cashflowCcy: Currency.Base
        });

        expectedCollateral = status.collateral + discountFee(1 ether - slippage(2.2 ether));
        expectedDebt = status.debt + 2200e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 2200e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(1 ether - slippage(2.2 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -2200e6, output: int256(discountSlippage(2.2 ether)) }),
            cashflow: -1.2 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(1 ether - slippage(2.2 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 2200e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(1 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 1.2 ether, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(1 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, Withdraw 100 (take 4.1k new debt)
    function testScenario14() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 4 ether, cashflow: -100e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral + discountFee(discountSlippage(4 ether));
        expectedDebt = status.debt + 4100e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 4100e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: -100e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 100e6, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH, Withdraw 1.2k (take 2.2k new debt)
    function testScenario15() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -1200e6,
            cashflowCcy: Currency.Quote
        });

        expectedCollateral = status.collateral + discountFee(discountSlippage(1 ether));
        expectedDebt = status.debt + 2200e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 2200e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(1 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -1000e6, output: int256(discountSlippage(1 ether)) }),
            cashflow: -1200e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(1 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 1000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(1 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 1200e6, "trader quote balance");

        _assertTreasuryBalance(totalFee(1 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay debt with proceeds
    function testScenario16() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) =
            env.positionActions().closePosition({ positionId: positionId, quantity: 4 ether, cashflow: 0, cashflowCcy: Currency.None });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote);

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: 0,
            cashflowCcy: Currency.None,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 5 ETH for ~5k, repay debt with proceeds
    function testScenario17() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 1 ether,
            cashflowCcy: Currency.Base
        });

        // TODO we are flash loaning more than what we need in cases like this, worth the extra complexity to fix it?
        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, 1 ether + discountFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(1000e6 + discountFee(4000e6) - expectedFlashLoanFeeInQuote);

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(1 ether + discountFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(1000e6 + discountFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: 1 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, 1 ether + discountFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay debt worth ~5k
    function testScenario18() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 1000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote) - 1000e6;

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: 1000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1.5 ETH for ~1.5k, withdraw 2.5 ETH, repay ~1.5k
    function testScenario19() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -2.5 ether,
            cashflowCcy: Currency.Base
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, 1.5 ether - totalFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(1500e6 - totalFee(4000e6) - expectedFlashLoanFeeInQuote);

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(1.5 ether - totalFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(1500e6 - totalFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -2.5 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, 1.5 ether - totalFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 2.5 ether, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 1k, Sell 1k for ~1 ETH, withdraw ~2 ETH
    function testScenario20() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2 ether,
            cashflowCcy: Currency.Base
        });

        expectedCollateral = status.collateral - 1 ether;
        expectedDebt = status.debt + 1000e6;

        expectedTrade = Trade({
            quantity: -1 ether,
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -1000e6, output: int256(discountSlippage(1 ether)) }),
            cashflow: -int256(discountSlippage(1 ether) + discountFee(1 ether)),
            cashflowCcy: Currency.Base,
            fee: totalFee(1 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 1000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(1 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), discountSlippage(1 ether) + discountFee(1 ether), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(1 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~1.5k debt, withdraw 2.5k
    function testScenario21() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -2500e6,
            cashflowCcy: Currency.Quote
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote) + 2500e6;

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -2500e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 2500e6, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1 ETH for ~1k, take ~1k debt, withdraw 2k
    function testScenario22() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(1 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 1 ether;
        expectedDebt = status.debt + 2000e6 - discountSlippage(discountFee(1000e6) - expectedFlashLoanFeeInQuote);

        expectedTrade = Trade({
            quantity: -1 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(1 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(1000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -2000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(1 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(1 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(1 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 2000e6, "trader quote balance");

        _assertTreasuryBalance(totalFee(1 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 6 ETH for ~6k, repay ~6k, withdraw 4 ETH
    function testScenario23() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        // refresh debt value
        status = env.quoter().positionStatus(positionId);
        uint256 debtInBase = status.debt.mulDiv(1e18, 1000e6);
        assertApproxEqRelDecimal(status.collateral, 10 ether, 0.01e18, instrument.baseDecimals, "status.collateral");
        assertApproxEqRelDecimal(status.debt, 6000e6, 0.01e18, instrument.quoteDecimals, "status.debt");
        assertApproxEqRelDecimal(debtInBase, 6 ether, 0.01e18, instrument.baseDecimals, "debtInBase");

        env.positionActions().setSlippageTolerance(DEFAULT_SLIPPAGE_TOLERANCE);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: type(uint256).max,
            cashflow: 0,
            cashflowCcy: Currency.Base
        });

        uint256 swapAmountSlippage = slippage(debtInBase) * 2e4 / 1e4;
        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, debtInBase + swapAmountSlippage);

        expectedCollateral = 0;
        expectedDebt = 0;

        expectedTrade = Trade({
            quantity: -10 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(debtInBase + swapAmountSlippage), // swap just enough to repay debt with some fat
                output: int256(discountSlippage(status.debt + slippage(status.debt) * 2e4 / 1e4))
            }),
            cashflow: -int256(10 ether - (debtInBase + swapAmountSlippage) - totalFee(10 ether) - expectedFlashLoanFee),
            cashflowCcy: Currency.Base,
            fee: totalFee(10 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, debtInBase + swapAmountSlippage, "quote.swapAmount");

        _assertEqBase(
            instrument.base.balanceOf(TRADER),
            10 ether - (debtInBase + swapAmountSlippage) - totalFee(10 ether) - expectedFlashLoanFee,
            "trader base balance"
        );
        _assertEqQuote(vault.balanceOf(instrument.quote, TRADER), uint256(trade.swap.output) - status.debt, "trader quote balance");
        _assertTreasuryBalance(totalFee(10 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 10 ETH for ~10k, repay 6k, withdraw ~4k
    function testScenario24() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: type(uint256).max,
            cashflow: 0,
            cashflowCcy: Currency.Quote
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(10 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = 0;
        expectedDebt = 0;

        expectedTrade = Trade({
            quantity: -10 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(10 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(10_000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -int256(discountSlippage(discountFee(10_000e6) - expectedFlashLoanFeeInQuote) - status.debt),
            cashflowCcy: Currency.Quote,
            fee: totalFee(10 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(10 ether) - expectedFlashLoanFee, "quote.swapAmount");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(
            instrument.quote.balanceOf(TRADER),
            discountSlippage(discountFee(10_000e6) - expectedFlashLoanFeeInQuote) - status.debt,
            "trader quote balance"
        );

        _assertTreasuryBalance(totalFee(10 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 2k, Sell 2k for ~2 ETH, withdraw ~2 ETH
    function testScenario25() public {
        (Quote memory quote, PositionId positionId,, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        quote = env.positionActions().modifyPosition({ positionId: positionId, cashflow: -1 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral;
        expectedDebt = status.debt + 1000e6;

        Trade memory emptyTrade;
        _assertPosition(positionId, emptyTrade);

        _assertEqBase(instrument.base.balanceOf(TRADER), discountSlippage(1 ether), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 2k, withdraw 2k
    function testScenario26() public {
        (Quote memory quote, PositionId positionId,, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote) = env.positionActions().modifyPosition({ positionId: positionId, cashflow: -1000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral;
        expectedDebt = status.debt + 1000e6;

        Trade memory emptyTrade;
        _assertPosition(positionId, emptyTrade);

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 1000e6, "trader quote balance");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Just withdraw 1 ETH, no spot trade needed
    function testScenario27() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -1 ether,
            cashflowCcy: Currency.Base
        });

        expectedCollateral = status.collateral - 1 ether;
        expectedDebt = status.debt;

        expectedTrade = Trade({
            quantity: -1 ether,
            forwardPrice: 0, // No swap happened, the subgraph will pull the price from the oracle
            swap: SwapInfo({ price: 0, inputCcy: Currency.None, input: 0, output: 0 }),
            cashflow: -int256(discountFee(1 ether)),
            cashflowCcy: Currency.Base,
            fee: totalFee(1 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);
        assertEq(toString(quote.swapCcy), toString(Currency.None), "quote.swapCcy");
        assertEq(quote.swapAmount, 0, "quote.swapAmount");

        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(1 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), discountFee(1 ether), "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(1 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH
    function testScenario28() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 5 ether, cashflow: 1 ether, cashflowCcy: Currency.Base });

        expectedCollateral = status.collateral + discountFee(5 ether - slippage(4 ether));
        expectedDebt = status.debt + 4000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 4000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(5 ether - slippage(4 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -4000e6, output: int256(discountSlippage(4 ether)) }),
            cashflow: 1 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(5 ether - slippage(4 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 4000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(5 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(5 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 5k for ~5 ETH but only borrow what the trader's not paying for (borrow 4k)
    function testScenario29() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        (quote, positionId, trade) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 5 ether, cashflow: 1000e6, cashflowCcy: Currency.Quote });

        expectedCollateral = status.collateral + discountFee(discountSlippage(5 ether));
        expectedDebt = status.debt + 4000e6 + _flashLoanFee(quote.flashLoanProvider, instrument.quote, 4000e6);

        expectedTrade = Trade({
            quantity: int256(discountFee(discountSlippage(5 ether))),
            forwardPrice: addSlippage(1000e6),
            swap: SwapInfo({ price: addSlippage(1000e6), inputCcy: Currency.Quote, input: -5000e6, output: int256(discountSlippage(5 ether)) }),
            cashflow: 1000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(discountSlippage(5 ether)),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Quote), "quote.swapCcy");
        _assertEqQuote(quote.swapAmount, 5000e6, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(5 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertTreasuryBalance(totalFee(5 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 3 ETH for ~3k, withdraw 1 ETH, repay ~3k
    function testScenario30() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -1 ether,
            cashflowCcy: Currency.Base
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, 3 ether - totalFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(3000e6 - totalFee(4000e6) - expectedFlashLoanFeeInQuote);

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(3 ether - totalFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(3000e6 - totalFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -1 ether,
            cashflowCcy: Currency.Base,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, 3 ether - totalFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 1 ether, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 0, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~3k debt, withdraw 1k
    function testScenario31() public {
        (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status) = _initialPosition();

        skip(1 seconds);

        (quote, trade) = env.positionActions().closePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -1000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 expectedFlashLoanFee = _flashLoanFee(quote.flashLoanProvider, instrument.base, discountFee(4 ether));
        uint256 expectedFlashLoanFeeInQuote = expectedFlashLoanFee.mulDiv(1000e6, 1e18);

        expectedCollateral = status.collateral - 4 ether;
        expectedDebt = status.debt - discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote) + 1000e6;

        expectedTrade = Trade({
            quantity: -4 ether,
            forwardPrice: discountSlippage(1000e6),
            swap: SwapInfo({
                price: discountSlippage(1000e6),
                inputCcy: Currency.Base,
                input: -int256(discountFee(4 ether) - expectedFlashLoanFee),
                output: int256(discountSlippage(discountFee(4000e6) - expectedFlashLoanFeeInQuote))
            }),
            cashflow: -1000e6,
            cashflowCcy: Currency.Quote,
            fee: totalFee(4 ether),
            feeCcy: Currency.Base
        });

        _assertPosition(positionId, trade);
        _assertQuote(positionId, quote);

        assertEq(toString(quote.swapCcy), toString(Currency.Base), "quote.swapCcy");
        _assertEqBase(quote.swapAmount, discountFee(4 ether) - expectedFlashLoanFee, "quote.swapAmount");
        assertEq(toString(quote.feeCcy), toString(Currency.Base), "quote.feeCcy");
        assertApproxEqRelDecimal(quote.fee, totalFee(4 ether), 0.0000001e18, instrument.baseDecimals, "quote.fee");

        _assertEqBase(instrument.base.balanceOf(TRADER), 0, "trader base balance");
        _assertEqQuote(instrument.quote.balanceOf(TRADER), 1000e6, "trader quote balance");

        _assertTreasuryBalance(totalFee(4 ether));

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // ============================ HELPERS ============================

    function _initialPosition()
        private
        returns (Quote memory quote, PositionId positionId, Trade memory trade, PositionStatus memory status)
    {
        int256 previousSpread = poolStub.absoluteSpread();
        poolStub.setAbsoluteSpread(0);

        (address previousFeeModel, bytes memory previousFeeModelBytecode) = env.etchNoFeeModel();

        (quote, positionId, trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        poolStub.setAbsoluteSpread(previousSpread);

        vm.etch(previousFeeModel, previousFeeModelBytecode);

        status = env.quoter().positionStatus(positionId);
    }

    function _assertPosition(PositionId positionId, Trade memory trade) private {
        _assertEqBase(trade.quantity, expectedTrade.quantity, "trade.quantity");
        assertApproxEqAbsDecimal(trade.swap.price, expectedTrade.swap.price, 1, instrument.quoteDecimals, "trade.swap.price");

        assertEq(toString(trade.feeCcy), toString(expectedTrade.feeCcy), "trade.feeCcy");
        require(trade.feeCcy != Currency.Quote, "should not charge fees in quote");
        if (trade.feeCcy == Currency.Base) {
            // approx 0.001% due to swap not being precise
            assertApproxEqRelDecimal(trade.fee, expectedTrade.fee, 0.00001e18, instrument.baseDecimals, "trade.fee");
        }

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

        PositionStatus memory status = env.quoter().positionStatus(positionId);
        _assertEqBase(status.collateral, expectedCollateral, "collateral");
        _assertEqQuote(status.debt, expectedDebt, "debt");

        if (status.collateral > 0) assertTrue(contango.positionNFT().exists(positionId), "positionNFT.exists");
    }

    function _assertQuote(PositionId positionId, Quote memory quote) internal virtual {
        PositionStatus memory status = env.quoter().positionStatus(positionId);
        assertEq(quote.oracleData.unit, status.oracleData.unit, "quote.oracleData.unit");
        assertApproxEqAbs(
            quote.oracleData.collateral,
            status.oracleData.collateral,
            env.bounds(instrument.baseData.symbol).dust * quote.oracleData.unit / instrument.baseDecimals,
            "quote.oracleData.collateral"
        );
        assertApproxEqRel(
            quote.oracleData.debt,
            status.oracleData.debt,
            0.01e18, // 1%
            "quote.oracleData.debt"
        );
    }

    function _assertTreasuryBalance(uint256 _totalFee) private {
        uint256 protocolFee;

        if (address(env.feeManager().referralManager()) != address(0)) {
            protocolFee = env.feeManager().referralManager().calculateRewardDistribution(TRADER, _totalFee).protocol;
        }
        assertApproxEqAbsDecimal(
            vault.balanceOf(instrument.base, TREASURY),
            protocolFee,
            env.bounds(instrument.baseData.symbol).dust,
            instrument.baseDecimals,
            "treasury vault base balance"
        );
    }

    function _assertEqBase(int256 left, int256 right, string memory message) private {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, message);
    }

    function _assertEqBase(uint256 left, uint256 right, string memory message) private {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.baseData.symbol).dust, instrument.baseDecimals, message);
    }

    function _assertEqQuote(int256 left, int256 right, string memory message) private {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.quoteData.symbol).dust, instrument.quoteDecimals, message);
    }

    function _assertEqQuote(uint256 left, uint256 right, string memory message) private {
        assertApproxEqAbsDecimal(left, right, env.bounds(instrument.quoteData.symbol).dust, instrument.quoteDecimals, message);
    }

    function _flashLoanFee(IERC7399 flp, IERC20 asset, uint256 amount) private view returns (uint256) {
        bool hasFlashBorrow = contango.positionFactory().moneyMarket(mm).supportsInterface(type(IFlashBorrowProvider).interfaceId);
        return address(asset) == address(instrument.quote) && hasFlashBorrow ? 0 : flp.flashFee(address(asset), amount);
    }

}

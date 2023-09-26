//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

contract PositionValidationsFunctional is BaseTest {

    using SignedMath for *;
    using SafeCast for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;

    Contango contango;
    IVault vault;
    Maestro maestro;
    address uniswap;

    function setUp() public {
        env = provider(Network.Polygon);
        env.init();
        mm = MM_AAVE;
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        contango = env.contango();
        vault = env.vault();
        maestro = env.maestro();
        uniswap = env.uniswap();
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 3000
        });

        env.etchNoFeeModel();

        poolStub = UniswapPoolStub(poolAddress);

        env.positionActions().setSlippageTolerance(0);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
    }

    // Can't open a position with overspending
    function testValidation01(bool cashflowCcyId) public {
        Currency cashflowCcy = cashflowCcyId ? Currency.Quote : Currency.Base;
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        instrument = env.instruments(positionId.getSymbol());

        Quote memory quote = env.quoter().quoteOpen(
            OpenQuoteParams({
                positionId: positionId,
                quantity: 10 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );
        uint256 originalSwapAmount = quote.swapAmount;
        quote.swapAmount += 1; // Swap more than what the user wanted

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.ExcessiveInputQuote.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, originalSwapAmount, instrument.quoteDecimals, "limit");
        assertGt(actual, originalSwapAmount, "actual");
    }

    // Can't open a position over the limit price
    function testValidation02(bool cashflowCcyId) public {
        Currency cashflowCcy = cashflowCcyId ? Currency.Quote : Currency.Base;
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        instrument = env.instruments(positionId.getSymbol());

        Quote memory quote = env.quoter().quoteOpen(
            OpenQuoteParams({
                positionId: positionId,
                quantity: 10 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        poolStub.setAbsoluteSpread(1e6); // ~1%

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.PriceAboveLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertGt(actual, quote.price, "actual");
    }

    // Can't increase a position with overspending
    function testValidation03(bool cashflowCcyId) public {
        Currency cashflowCcy = cashflowCcyId ? Currency.Quote : Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteOpen(
            OpenQuoteParams({
                positionId: positionId,
                quantity: 1 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );
        uint256 originalSwapAmount = quote.swapAmount;
        quote.swapAmount += 1; // Swap more than what the user wanted

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.ExcessiveInputQuote.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, originalSwapAmount, instrument.quoteDecimals, "limit");
        assertGt(actual, originalSwapAmount, "actual");
    }

    // Can't increase a position over the limit price
    function testValidation04(bool cashflowCcyId) public {
        Currency cashflowCcy = cashflowCcyId ? Currency.Quote : Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteOpen(
            OpenQuoteParams({
                positionId: positionId,
                quantity: 1 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.PriceAboveLimit.selector, "error selector not expected");
        (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
        assertGt(actualPrice, quote.price, "actualPrice");
    }

    // Can't decrease a position and remove base due to over spending on swap
    function testValidation05() public {
        Currency cashflowCcy = Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteClose(
            CloseQuoteParams({
                positionId: positionId,
                quantity: 1 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );
        quote.swapAmount += 1; // Swap more than what the user wanted

        if (quote.cashflowUsed > 0) {
            env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());
        }

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: -quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.InsufficientBaseCashflow.selector, "error selector not expected");
        (int256 expected, int256 actual) = abi.decode(removeSelector(data), (int256, int256));
        assertEqDecimal(expected, quote.cashflowUsed, instrument.baseDecimals, "expected");
        assertEqDecimal(actual, quote.cashflowUsed + 1, instrument.baseDecimals, "actual");
    }

    // Can't decrease a position over the limit price due to slippage
    function testValidation06(bool cashflowCcyId) public {
        Currency cashflowCcy = cashflowCcyId ? Currency.Quote : Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteClose(
            CloseQuoteParams({
                positionId: positionId,
                quantity: 1 ether,
                leverage: 2e18,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );

        if (quote.cashflowUsed > 0) {
            env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());
        }

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: -quote.quantity.toInt256(),
                    cashflow: quote.cashflowUsed,
                    cashflowCcy: cashflowCcy,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.PriceBelowLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertLt(actual, quote.price, "actual");
    }

    // Can't fully close a position to base if overspending on swap
    function testValidation07() public {
        Currency cashflowCcy = Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteClose(
            CloseQuoteParams({
                positionId: positionId,
                quantity: type(uint256).max,
                leverage: 0,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                slippageTolerance: 0
            })
        );

        // accrue some interest on base between quoting and trading to ensure swap really won't use more than specified
        skip(2 seconds);

        bytes memory swapBytes = abi.encodeWithSelector(
            env.uniswapRouter().exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.swapAmount + 1, // swap overspends
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.expectRevert(bytes("STF")); // not enough funds available to do swap - uniswap safe transfer fails

        vm.prank(TRADER);
        contango.trade(
            TradeParams({
                positionId: positionId,
                quantity: type(int256).min,
                cashflow: 0,
                cashflowCcy: cashflowCcy,
                limitPrice: quote.price * (1e4 - DEFAULT_SLIPPAGE_TOLERANCE) / 1e4
            }),
            ExecutionParams({
                router: uniswap,
                spender: uniswap,
                swapAmount: quote.swapAmount,
                swapBytes: swapBytes,
                flashLoanProvider: quote.flashLoanProvider
            })
        );
    }

    // Can't modify a position with base over the limit price
    function testValidation08(bool decreaseLeverage) public {
        Currency cashflowCcy = Currency.Base;

        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        uint256 newLeverage = decreaseLeverage ? 1.5e18 : 2.5e18;
        quote = env.quoter().quoteModify(
            ModifyQuoteParams({ positionId: positionId, leverage: newLeverage, cashflow: 0, cashflowCcy: cashflowCcy })
        );

        if (decreaseLeverage) env.deposit(instrument.base, TRADER, quote.cashflowUsed.toUint256());

        bytes memory swapBytes;
        if (quote.swapCcy == Currency.Quote) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.quote, uint24(3000), instrument.base),
                    recipient: address(contango.spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        } else if (quote.swapCcy == Currency.Base) {
            swapBytes = abi.encodeWithSelector(
                env.uniswapRouter().exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(instrument.base, uint24(3000), instrument.quote),
                    recipient: address(contango.spotExecutor()),
                    amountIn: quote.swapAmount,
                    amountOutMinimum: 0 // UI's problem
                 })
            );
        }

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: 0,
                    cashflowCcy: cashflowCcy,
                    cashflow: quote.cashflowUsed,
                    limitPrice: quote.price
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        if (decreaseLeverage) {
            require(bytes4(data) == IContangoErrors.PriceBelowLimit.selector, "error selector not expected");
            (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
            assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
            assertLt(actualPrice, quote.price, "actualPrice");
        } else {
            require(bytes4(data) == IContangoErrors.PriceAboveLimit.selector, "error selector not expected");
            (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
            assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
            assertGt(actualPrice, quote.price, "actualPrice");
        }
    }

    // Can't open position with invalid instrument
    function testValidation09() public {
        Symbol invalidSymbol = Symbol.wrap("invalid");
        PositionId newPositionId = env.encoder().encodePositionId(invalidSymbol, mm, PERP, 0);

        vm.expectRevert(abi.encodeWithSelector(IContangoErrors.InvalidInstrument.selector, invalidSymbol));
        contango.trade(
            TradeParams({ positionId: newPositionId, quantity: 10 ether, cashflow: 6 ether, cashflowCcy: Currency.Base, limitPrice: 0 }),
            ExecutionParams({
                router: address(0),
                spender: address(0),
                swapAmount: 0,
                swapBytes: "",
                flashLoanProvider: IERC7399(address(0))
            })
        );
    }

    // Can open a position where the used flash loan provider is different than the one passed due to flash borrow
    function testValidation10() public {
        PositionId newPositionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: newPositionId,
            quantity: 10 ether,
            leverage: 0,
            cashflow: 6 ether,
            cashflowCcy: Currency.Base
        });

        // force balancer flash loan provider
        quote.flashLoanProvider = env.balancerFLP();

        env.positionActions().openPosition({
            positionId: newPositionId,
            cashflowCcy: Currency.Base,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: env.positionActions().prepareOpenPosition(newPositionId, quote, Currency.Base)
        });
    }

    // Tries to repay more than existing debt with excessive quote cashflow on an increase
    function testValidation11() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 1 ether,
            leverage: 0,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        (, Trade memory trade) = env.positionActions().openPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            slippageTolerance: DEFAULT_SLIPPAGE_TOLERANCE,
            quote: quote,
            swapBytes: env.positionActions().prepareOpenPosition(positionId, quote, cashflowCcy)
        });

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // // Tries to repay more than existing debt with extra cashflow on a decrease
    function testValidation12() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 1 ether,
            leverage: 0,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        Trade memory trade = env.positionActions().closePosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            quote: quote,
            swapBytes: env.positionActions().prepareClosePosition(positionId, quote, cashflowCcy)
        });

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // // Tries to repay more than existing debt with extra cashflow on a modify
    function testValidation13() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        Quote memory quote = env.positionActions().quoteModifyPosition({
            positionId: positionId,
            leverage: 0,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        Trade memory trade = env.positionActions().modifyPosition({
            positionId: positionId,
            cashflowCcy: cashflowCcy,
            quote: quote,
            swapBytes: env.positionActions().prepareModifyPosition(positionId, quote, cashflowCcy)
        });

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Can't fully close a position without cashflow ccy
    function testValidation14() public {
        (Quote memory quote, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.quoter().quoteClose(
            CloseQuoteParams({
                positionId: positionId,
                quantity: type(uint256).max,
                leverage: 0,
                cashflow: 0,
                cashflowCcy: Currency.None,
                slippageTolerance: 0
            })
        );

        bytes memory swapBytes;

        vm.prank(TRADER);
        (bool success, bytes memory data) = address(maestro).call(
            abi.encodeWithSelector(
                contango.trade.selector,
                TradeParams({
                    positionId: positionId,
                    quantity: type(int128).min,
                    cashflow: 0,
                    cashflowCcy: Currency.None, // enforce None
                    limitPrice: quote.price * (1e4 - DEFAULT_SLIPPAGE_TOLERANCE) / 1e4
                }),
                ExecutionParams({
                    router: uniswap,
                    spender: uniswap,
                    swapAmount: quote.swapAmount,
                    swapBytes: swapBytes,
                    flashLoanProvider: quote.flashLoanProvider
                })
            )
        );

        require(!success, "should have failed");
        require(bytes4(data) == IContangoErrors.CashflowCcyRequired.selector, "error selector not expected");
    }

    // Calls claimRewards on the underlying money market
    function testValidation15() public {
        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        skip(10 days);

        IMoneyMarket moneyMarket = env.positionFactory().moneyMarket(positionId);
        vm.expectCall(
            address(moneyMarket),
            abi.encodeWithSelector(IMoneyMarket.claimRewards.selector, positionId, instrument.base, instrument.quote, TRADER)
        );

        vm.prank(TRADER);
        contango.claimRewards(positionId, TRADER);

        skip(10 days);

        // after closing
        env.positionActions().closePosition({ positionId: positionId, quantity: type(uint128).max, cashflow: 0, cashflowCcy: Currency.Base });

        vm.expectCall(
            address(moneyMarket),
            abi.encodeWithSelector(IMoneyMarket.claimRewards.selector, positionId, instrument.base, instrument.quote, TRADER)
        );

        vm.prank(TRADER);
        contango.claimRewards(positionId, TRADER);
    }

}

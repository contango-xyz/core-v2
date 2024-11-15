//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract PositionValidationsFunctional is BaseTest, IContangoErrors, IContangoEvents {

    using SignedMath for *;
    using SafeCast for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    PositionActions internal positionActions;
    IUnderlyingPositionFactory internal positionFactory;

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
        positionActions = env.positionActions();
        positionFactory = env.positionFactory();
        vault = env.vault();
        maestro = env.maestro();
        uniswap = env.uniswap();
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        poolStub = UniswapPoolStub(poolAddress);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testValidation02_base() public {
        _testValidation02(Currency.Base);
    }

    function testValidation02_quote() public {
        _testValidation02(Currency.Quote);
    }

    // Can't open a position over the limit price
    function _testValidation02(Currency cashflowCcy) internal {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        instrument = env.instruments(positionId.getSymbol());

        TSQuote memory quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 10 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: 0
        });

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        poolStub.setAbsoluteSpread(1e6); // ~1%

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == PriceAboveLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertGt(actual, quote.price, "actual");
    }

    function testValidation04_base() public {
        _testValidation04(Currency.Base);
    }

    function testValidation04_quote() public {
        _testValidation04(Currency.Quote);
    }

    // Can't increase a position over the limit price
    function _testValidation04(Currency cashflowCcy) internal {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        instrument = env.instruments(positionId.getSymbol());

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 1 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: 0
        });

        env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == PriceAboveLimit.selector, "error selector not expected");
        (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
        assertGt(actualPrice, quote.price, "actualPrice");
    }

    // Can't decrease a position and remove base due to over spending on swap
    function testValidation05() public {
        Currency cashflowCcy = Currency.Base;

        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -1 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: 0
        });
        quote.execParams.swapAmount = quote.execParams.swapAmount * 1.001e18 / 1e18; // Swap more than what the user wanted

        if (quote.cashflowUsed > 0) {
            env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());
        }

        quote.execParams.swapBytes = abi.encodeWithSelector(
            SwapRouter02.exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.base, uint24(500), instrument.quote),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.execParams.swapAmount,
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == InsufficientBaseCashflow.selector, "error selector not expected");
        (int256 expected, int256 actual) = abi.decode(removeSelector(data), (int256, int256));
        assertEqDecimal(expected, quote.cashflowUsed, instrument.baseDecimals, "expected");
        assertGtDecimal(actual, quote.cashflowUsed, instrument.baseDecimals, "actual"); // negative values
    }

    function testValidation06_base() public {
        _testValidation06(Currency.Base);
    }

    function testValidation06_quote() public {
        _testValidation06(Currency.Quote);
    }

    // Can't decrease a position over the limit price due to slippage
    function _testValidation06(Currency cashflowCcy) internal {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -1 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: 0
        });

        if (quote.cashflowUsed > 0) {
            env.deposit(cashflowCcy == Currency.Quote ? instrument.quote : instrument.base, TRADER, quote.cashflowUsed.toUint256());
        }

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == PriceBelowLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertLt(actual, quote.price, "actual");
    }

    // Can't fully close a position to base if overspending on swap
    function testValidation07() public {
        Currency cashflowCcy = Currency.Base;

        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: type(int256).min,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            slippageTolerance: 0
        });

        // accrue some interest on base between quoting and trading to ensure swap really won't use more than specified
        skip(2 seconds);

        quote.execParams.swapBytes = abi.encodeWithSelector(
            SwapRouter02.exactInput.selector,
            SwapRouter02.ExactInputParams({
                path: abi.encodePacked(instrument.base, uint24(500), instrument.quote),
                recipient: address(contango.spotExecutor()),
                amountIn: quote.execParams.swapAmount + 1,
                amountOutMinimum: 0 // UI's problem
             })
        );

        vm.expectRevert(bytes("STF")); // not enough funds available to do swap - uniswap safe transfer fails

        vm.prank(TRADER);
        contango.trade(quote.tradeParams, quote.execParams);
    }

    function testValidation08_increaseLeverage() public {
        _testValidation08(2.5e18);
    }

    function testValidation08_decreaseLeverage() public {
        _testValidation08(1.5e18);
    }

    // Can't modify a position with base over the limit price
    function _testValidation08(uint256 newLeverage) internal {
        Currency cashflowCcy = Currency.Base;

        uint256 initialLeverage = 2e18;
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: initialLeverage,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        instrument = env.instruments(positionId.getSymbol());

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 0,
            slippageTolerance: 0,
            leverage: newLeverage,
            cashflow: 0,
            cashflowCcy: cashflowCcy
        });

        bool decreaseLeverage = newLeverage < initialLeverage;

        if (decreaseLeverage) env.deposit(instrument.base, TRADER, quote.cashflowUsed.toUint256());

        poolStub.setAbsoluteSpread(1e6); // ~0.1%

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        if (decreaseLeverage) {
            require(bytes4(data) == PriceBelowLimit.selector, "error selector not expected");
            (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
            assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
            assertLt(actualPrice, quote.price, "actualPrice");
        } else {
            require(bytes4(data) == PriceAboveLimit.selector, "error selector not expected");
            (uint256 limitPrice, uint256 actualPrice) = abi.decode(removeSelector(data), (uint256, uint256));
            assertEqDecimal(limitPrice, quote.price, instrument.quoteDecimals, "limitPrice");
            assertGt(actualPrice, quote.price, "actualPrice");
        }
    }

    // Can't open position with invalid instrument
    function testValidation09() public {
        Symbol invalidSymbol = Symbol.wrap("invalid");
        PositionId newPositionId = env.encoder().encodePositionId(invalidSymbol, mm, PERP, 0);

        vm.expectRevert(abi.encodeWithSelector(InvalidInstrument.selector, invalidSymbol));
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
        TSQuote memory quote = positionActions.quoteWithCashflow({
            positionId: newPositionId,
            quantity: 10 ether,
            cashflow: 6 ether,
            cashflowCcy: Currency.Base
        });

        // force flash loan provider
        quote.execParams.flashLoanProvider = new TestFLP();

        positionActions.submitTrade(newPositionId, quote, Currency.Base);
    }

    // Tries to repay more than existing debt with excessive quote cashflow on an increase
    function testValidation11() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        TSQuote memory quote = positionActions.quoteWithCashflow({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        (, Trade memory trade) = positionActions.submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        env.checkInvariants(instrument, positionId);
    }

    // Tries to repay more than existing debt with extra cashflow on a decrease
    function testValidation12() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        TSQuote memory quote = positionActions.quoteWithCashflow({
            positionId: positionId,
            quantity: -1 ether,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        (, Trade memory trade) = positionActions.submitTrade(positionId, quote, cashflowCcy);

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        uint256 contangoBaseDustTolerance = 1 ether * 0.00001e18 / 1e18;
        env.checkInvariants(instrument, positionId, contangoBaseDustTolerance);
    }

    // // Tries to repay more than existing debt with extra cashflow on a modify
    function testValidation13() public {
        Currency cashflowCcy = Currency.Quote;

        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: cashflowCcy
        });

        skip(1 seconds);

        int256 excessiveCashflow = 20_000e6; // excessive cashflow

        TSQuote memory quote = positionActions.quoteWithCashflow({
            positionId: positionId,
            quantity: 0,
            cashflow: excessiveCashflow,
            cashflowCcy: cashflowCcy
        });
        int256 expectedCashflow = quote.cashflowUsed;
        quote.cashflowUsed = excessiveCashflow; // enforce excessive cashflow

        (, Trade memory trade) = positionActions.submitTrade({ positionId: positionId, cashflowCcy: cashflowCcy, quote: quote });

        assertEqDecimal(trade.cashflow, expectedCashflow, instrument.quote.decimals(), "cashflow");

        env.checkInvariants(instrument, positionId);
    }

    // Can't fully close a position without cashflow ccy
    function testValidation14() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        skip(1 seconds);

        quote = positionActions.quoteFullyClose(positionId, Currency.None);

        vm.prank(TRADER);
        (bool success, bytes memory data) =
            address(maestro).call(abi.encodeWithSelector(contango.trade.selector, quote.tradeParams, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == CashflowCcyRequired.selector, "error selector not expected");
    }

    // Calls claimRewards on the underlying money market
    function testValidation15() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        skip(10 days);

        IMoneyMarket moneyMarket = positionFactory.moneyMarket(positionId);
        vm.expectCall(
            address(moneyMarket),
            abi.encodeWithSelector(IMoneyMarket.claimRewards.selector, positionId, instrument.base, instrument.quote, TRADER)
        );

        vm.prank(TRADER);
        contango.claimRewards(positionId, TRADER);

        skip(10 days);

        // after closing
        positionActions.closePosition({ positionId: positionId, quantity: type(uint128).max, cashflow: 0, cashflowCcy: Currency.Base });

        vm.expectCall(
            address(moneyMarket),
            abi.encodeWithSelector(IMoneyMarket.claimRewards.selector, positionId, instrument.base, instrument.quote, TRADER)
        );

        vm.prank(TRADER);
        contango.claimRewards(positionId, TRADER);
    }

    function testValidation16() public {
        address to = address(0xb0b);

        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        skip(10 days);

        // after closing
        positionActions.closePosition({ positionId: positionId, quantity: type(uint128).max, cashflow: 0, cashflowCcy: Currency.Base });

        vm.expectEmit(true, true, true, true);
        emit PositionDonated(positionId, TRADER, to);

        vm.prank(TRADER);
        contango.donatePosition(positionId, to);

        assertEq(contango.lastOwner(positionId), to, "lastOwner");
    }

}

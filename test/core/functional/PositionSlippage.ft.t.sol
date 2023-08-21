//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

/// @dev scenario implementation for https://docs.google.com/spreadsheets/d/1jbb2yy9RfumOwdd6UTo4fzx0Z28FJ-GiRFGN6DKeE9Q/edit#gid=0
contract PositionSlippageFunctional is BaseTest {

    using SafeCast for *;
    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarket internal mm;
    PositionActions internal positionActions;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        positionActions = env.positionActions();
        mm = MM_AAVE;
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 3000
        });

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
    }

    // Borrow 6k, Sell 6k for ~6 ETH
    function testScenario1() public {
        Currency cashflowCcy = Currency.Base;
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 6k, Sell 10k for ~10 ETH
    function testScenario2() public {
        Currency cashflowCcy = Currency.Quote;
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 4k, Sell 4k for ~4 ETH
    function testScenario3() public {
        Currency cashflowCcy = Currency.None;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH
    function testScenario4() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 3 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Scenario 05 is just adding/removing quote, no swap = no slippage check

    // Lend 4 ETH & Sell 2 ETH, repay debt with the proceeds
    function testScenario6() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 6 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 2 ETH for ~2k, repay debt with the proceeds
    function testScenario7() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteModifyPosition({
            positionId: positionId,
            leverage: 0,
            cashflow: 2 ether,
            cashflowCcy: Currency.Base
        });

        (bool success, bytes memory data) = _movePriceAndModify(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH but only borrow what the trader's not paying for (borrow 1k)
    function testScenario8() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 3000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, no changes on debt
    function testScenario9() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 4000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH & repay debt with 2k excess cashflow
    function testScenario10() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 6000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Scenario 11 is just adding/removing quote, no swap = no slippage check

    // Sell 5k for ~5 ETH, Withdraw 1, Lend ~4 (take 5k new debt)
    function testScenario12() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -1 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 3k for ~3 ETH, Withdraw 2, Lend ~1 (take 3k new debt)
    function testScenario13() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4k for ~4 ETH, Withdraw 1k (take 5k new debt)
    function testScenario14() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -1000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1k for ~1 ETH, Withdraw 2k (take 3k new debt)
    function testScenario15() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay debt with proceeds
    function testScenario16() public {
        Currency cashflowCcy = Currency.None;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 5 ETH for ~5k, repay debt with proceeds
    function testScenario17() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 1 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay debt worth ~5k
    function testScenario18() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: 1000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1 ETH for ~1k, withdraw 3 ETH, repay ~1k
    function testScenario19() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -3 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 1k, Sell 1k for ~1 ETH, withdraw ~2 ETH
    function testScenario20() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~1k debt, withdraw 3k
    function testScenario21() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -3000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 1 ETH for ~1k, take ~1k debt, withdraw 2k
    function testScenario22() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 1 ether,
            cashflow: -2000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 6 ETH for ~6k, repay 6k, withdraw 4 ETH
    function testScenario23() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: type(uint256).max,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 10 ETH for ~10k, repay 6k, withdraw ~4k
    function testScenario24() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: type(uint256).max,
            cashflow: 0,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Borrow 2k, Sell 2k for ~2 ETH, withdraw ~2 ETH
    function testScenario25() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteModifyPosition({
            positionId: positionId,
            leverage: 0,
            cashflow: -2 ether,
            cashflowCcy: Currency.Base
        });

        (bool success, bytes memory data) = _movePriceAndModify(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Scenario 26 is just adding/removing quote, no swap = no slippage check
    // Scenario 27 is just adding/removing quote, no swap = no slippage check

    // Sell 4k for ~4 ETH
    function testScenario28() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 5 ether,
            cashflow: 1 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 5k for ~5 ETH but only borrow what the trader's not paying for (borrow 4k)
    function testScenario29() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        Quote memory quote = env.positionActions().quoteOpenPosition({
            positionId: positionId,
            quantity: 5 ether,
            cashflow: 1000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndOpen(positionId, quote, cashflowCcy);

        _assertPriceAboveLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 3 ETH for ~3k, withdraw 1 ETH, repay ~3k
    function testScenario30() public {
        Currency cashflowCcy = Currency.Base;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -1 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // Sell 4 ETH for ~4k, repay ~3k debt, withdraw 1k
    function testScenario31() public {
        Currency cashflowCcy = Currency.Quote;
        (, PositionId positionId,) = _initialPosition();

        skip(1 seconds);

        Quote memory quote = env.positionActions().quoteClosePosition({
            positionId: positionId,
            quantity: 4 ether,
            cashflow: -1000e6,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });

        (bool success, bytes memory data) = _movePriceAndClose(positionId, quote, cashflowCcy);

        _assertPriceBelowLimit(success, data, quote);

        env.checkInvariants(instrument, positionId, quote.flashLoanProvider);
    }

    // ============================ HELPERS ============================

    function _initialPosition() private returns (Quote memory quote, PositionId positionId, Trade memory trade) {
        (quote, positionId, trade) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });
    }

    function _movePriceAndOpen(PositionId positionId, Quote memory quote, Currency cashflowCcy)
        private
        returns (bool success, bytes memory data)
    {
        bytes memory swapBytes = env.positionActions().prepareOpenPosition(positionId, quote, cashflowCcy);

        env.spotStub().movePrice(instrument.baseData, int256(DEFAULT_SLIPPAGE_TOLERANCE * 1e14));

        (IERC20 _cashflowToken, uint256 value) = positionActions.prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        try positionActions.executeTrade(
            TradeParams({
                positionId: positionId,
                quantity: quote.quantity.toInt256(),
                cashflow: quote.cashflowUsed,
                cashflowCcy: cashflowCcy,
                limitPrice: quote.price
            }),
            ExecutionParams({
                router: env.uniswap(),
                spender: env.uniswap(),
                swapAmount: quote.swapAmount,
                swapBytes: swapBytes,
                flashLoanProvider: quote.flashLoanProvider
            }),
            _cashflowToken,
            value
        ) {
            success = true;
        } catch (bytes memory _data) {
            success = false;
            data = _data;
        }
    }

    function _movePriceAndClose(PositionId positionId, Quote memory quote, Currency cashflowCcy)
        private
        returns (bool success, bytes memory data)
    {
        bytes memory swapBytes;
        swapBytes = env.positionActions().prepareClosePosition(positionId, quote, cashflowCcy);

        env.spotStub().movePrice(instrument.baseData, -int256(DEFAULT_SLIPPAGE_TOLERANCE * 1e14));

        (IERC20 _cashflowToken, uint256 value) = positionActions.prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        try positionActions.executeTrade(
            TradeParams({
                positionId: positionId,
                quantity: -quote.quantity.toInt256(),
                cashflow: quote.cashflowUsed,
                cashflowCcy: cashflowCcy,
                limitPrice: quote.price
            }),
            ExecutionParams({
                router: env.uniswap(),
                spender: env.uniswap(),
                swapAmount: quote.swapAmount,
                swapBytes: swapBytes,
                flashLoanProvider: quote.flashLoanProvider
            }),
            _cashflowToken,
            value
        ) {
            success = true;
        } catch (bytes memory _data) {
            success = false;
            data = _data;
        }
    }

    function _movePriceAndModify(PositionId positionId, Quote memory quote, Currency cashflowCcy)
        private
        returns (bool success, bytes memory data)
    {
        bytes memory swapBytes = env.positionActions().prepareModifyPosition(positionId, quote, cashflowCcy);

        int256 priceMovement = quote.cashflowUsed > 0 ? -int256(DEFAULT_SLIPPAGE_TOLERANCE) : int256(DEFAULT_SLIPPAGE_TOLERANCE);
        env.spotStub().movePrice(instrument.baseData, priceMovement * int256(1e14));

        (IERC20 _cashflowToken, uint256 value) = positionActions.prepareCashflow(positionId, cashflowCcy, quote.cashflowUsed);

        try positionActions.executeTrade(
            TradeParams({
                positionId: positionId,
                quantity: quote.quantity.toInt256(),
                cashflow: quote.cashflowUsed,
                cashflowCcy: cashflowCcy,
                limitPrice: quote.price
            }),
            ExecutionParams({
                router: env.uniswap(),
                spender: env.uniswap(),
                swapAmount: quote.swapAmount,
                swapBytes: swapBytes,
                flashLoanProvider: quote.flashLoanProvider
            }),
            _cashflowToken,
            value
        ) {
            success = true;
        } catch (bytes memory _data) {
            success = false;
            data = _data;
        }
    }

    function _assertPriceAboveLimit(bool success, bytes memory data, Quote memory quote) private {
        require(!success, "should have failed");
        require(bytes4(data) == IContango.PriceAboveLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertEqDecimal(actual, quote.price * (1e4 + DEFAULT_SLIPPAGE_TOLERANCE) / 1e4, instrument.quoteDecimals, "actual");
    }

    function _assertPriceBelowLimit(bool success, bytes memory data, Quote memory quote) private {
        require(!success, "should have failed");
        require(bytes4(data) == IContango.PriceBelowLimit.selector, "error selector not expected");
        (uint256 limit, uint256 actual) = abi.decode(removeSelector(data), (uint256, uint256));
        assertEqDecimal(limit, quote.price, instrument.quoteDecimals, "limit");
        assertApproxEqRelDecimal(
            actual,
            quote.price * (1e4 - DEFAULT_SLIPPAGE_TOLERANCE) / 1e4,
            0.000001e18, // 0.0001% - negligible to cover skip(1 seconds) induced dust
            instrument.quoteDecimals,
            "actual"
        );
    }

}

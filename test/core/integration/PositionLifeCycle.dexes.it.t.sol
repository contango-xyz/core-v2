//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract PositionLifeCycleDexes is BaseTest {

    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    Contango internal contango;
    IVault internal vault;
    IMaestro internal maestro;
    TSQuoter internal quoter;

    address internal trader;

    uint256 internal slippageTolerance;

    TSQuote quote;
    TradeParams tradeParams;
    ExecutionParams execParams;

    function setUp() public {
        env = provider(Network.Polygon);
        env.init(0);
        contango = env.contango();
        vault = env.vault();
        maestro = env.maestro();
        quoter = env.tsQuoter();

        slippageTolerance = 0.003e18;

        trader = makeAddr("Trader");

        mm = MM_AAVE;
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
    }

    function testSinglePoolUniswap() public {
        _usingDex("uniswap-single-pool");
    }

    function testRealBestPrice() public {
        _usingDex("");
    }

    function testRealUniswap() public {
        _usingDex("uniswap");
    }

    function testRealParaswap() public {
        _usingDex("paraswap");
    }

    function testRealKyberswap() public {
        _usingDex("kyberswap");
    }

    function testReal1Inch() public {
        _usingDex("1inch");
    }

    function testReal0x() public {
        _usingDex("0x");
    }

    function testRealOpenOcean() public {
        _usingDex("open-ocean");
    }

    function testRealLiFi() public {
        _usingDex("li-fi");
    }

    function testRealOdos() public {
        _usingDex("odos");
    }

    function testRealFirebird() public {
        _usingDex("firebird");
    }

    function testRealRango() public {
        _usingDex("rango");
    }

    function testRealChangelly() public {
        _usingDex("changelly");
    }

    function testRealBalmy() public {
        _usingDex("balmy");
    }

    function testRealWido() public {
        _usingDex("wido");
    }

    function testRealPortalsFi() public {
        _usingDex("portals-fi");
    }

    function _usingDex(string memory dex) internal {
        if (!vm.envOr("RUN_REAL_IT_TESTS", false)) return;

        int256 quantity = 100 ether;
        uint256 leverage = 2e18;
        Currency cashflowCcy = Currency.Quote;
        PositionId positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 0);

        quote = quoter.quoteRealDex(positionId, quantity, leverage, 0, cashflowCcy, slippageTolerance, dex);
        tradeParams = TradeParams({
            positionId: positionId,
            quantity: quote.quantity,
            cashflow: quote.cashflowUsed,
            cashflowCcy: cashflowCcy,
            limitPrice: type(uint128).max
        });
        execParams = quote.execParams;

        env.dealAndApprove(instrument.quote, trader, uint256(quote.cashflowUsed), address(vault));
        vm.prank(trader);
        maestro.deposit(instrument.quote, uint256(quote.cashflowUsed));

        Trade memory trade;
        vm.prank(trader);
        (positionId, trade) = maestro.trade(tradeParams, execParams);
        console.log("Position opened at %s", trade.swap.price);

        assertEqDecimal(instrument.base.balanceOf(address(contango)), 0, instrument.baseDecimals, "contango base dust");
        assertEqDecimal(instrument.quote.balanceOf(address(contango)), 0, instrument.quoteDecimals, "contango quote dust");
        assertEqDecimal(vault.balanceOf(instrument.base, address(contango)), 0, instrument.baseDecimals, "vault base dust");
        assertEqDecimal(vault.balanceOf(instrument.quote, address(contango)), 0, instrument.quoteDecimals, "vault quote dust");

        skip(1 seconds);

        quote = quoter.quoteRealDex(positionId, type(int128).min, 0, 0, cashflowCcy, slippageTolerance, dex);
        tradeParams =
            TradeParams({ positionId: positionId, quantity: type(int128).min, cashflow: 0, cashflowCcy: cashflowCcy, limitPrice: 0 });
        execParams = quote.execParams;

        vm.prank(trader);
        (, trade) = maestro.trade(tradeParams, execParams);
        console.log("Position closed at %s", trade.swap.price);
        vm.prank(trader);
        maestro.withdraw(instrument.quote, uint256(-trade.cashflow), trader);

        assertApproxEqAbsDecimal(instrument.base.balanceOf(address(contango)), 0, 1e7, instrument.baseDecimals, "contango base dust");
        assertEqDecimal(instrument.quote.balanceOf(address(contango)), 0, instrument.quoteDecimals, "contango quote dust");
        assertEqDecimal(vault.balanceOf(instrument.base, address(contango)), 0, instrument.baseDecimals, "vault base dust");
        assertEqDecimal(vault.balanceOf(instrument.quote, address(contango)), 0, instrument.quoteDecimals, "vault quote dust");

        assertApproxEqRelDecimal(
            instrument.quote.balanceOf(address(trader)), uint256(-quote.cashflowUsed), 0.01e18, instrument.quoteDecimals, "cashflow"
        );
    }

}

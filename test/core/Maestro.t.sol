//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "forge-std/console.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract MaestroTest is BaseTest, IMaestroEvents, GasSnapshot {

    using SignedMath for *;
    using SafeCast for *;

    Env internal env;
    TestInstrument internal instrument;
    PositionActions internal positionActions;

    IVault internal vault;
    Maestro internal maestro;
    Contango internal contango;
    IOrderManager internal orderManager;
    PositionNFT internal positionNFT;
    SwapRouter02 internal router;
    address internal spotExecutor;

    IERC20 internal usdc;
    IERC20 internal weth;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        positionActions = env.positionActions();

        vault = env.vault();
        maestro = env.maestro();
        contango = env.contango();
        orderManager = env.orderManager();
        positionNFT = contango.positionNFT();
        router = env.uniswapRouter();
        spotExecutor = address(maestro.spotExecutor());

        usdc = env.token(USDC);
        weth = env.token(WETH);

        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testDeposit() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));

        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testDepositNative() public {
        vm.deal(TRADER, 10 ether);

        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        assertEq(vault.balanceOf(weth, TRADER), 10 ether, "trader vault balance");
    }

    function testDepositWithPermit_PermitAmount() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 10_000e6, address(vault));

        vm.prank(TRADER);
        maestro.depositWithPermit(usdc, signedPermit, 10_000e6);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testDepositWithPermit_LessThanPermitAmount() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 10_000e6, address(vault));

        vm.prank(TRADER);
        maestro.depositWithPermit(usdc, signedPermit, 9000e6);

        assertEq(vault.balanceOf(usdc, TRADER), 9000e6, "trader vault balance");
    }

    function testDepositWithPermit2_LessThanPermitAmount() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit2(usdc, TRADER, TRADER_PK, 10_000e6, address(maestro));

        vm.prank(TRADER);
        maestro.depositWithPermit2(usdc, signedPermit, 9000e6);

        assertEq(vault.balanceOf(usdc, TRADER), 9000e6, "trader vault balance");
    }

    function testSwapAndDeposit() public {
        uint256 amount = 10 ether;
        env.dealAndApprove(weth, TRADER, amount, address(maestro));

        SwapData memory swapData = _swap(router, weth, usdc, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndDeposit(weth, usdc, swapData);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositNative() public {
        uint256 amount = 10 ether;
        vm.deal(TRADER, amount);

        SwapData memory swapData = _swap(router, weth, usdc, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndDepositNative{ value: amount }(usdc, swapData);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositWithPermit() public {
        uint256 amount = 10 ether;

        SwapData memory swapData = _swap(router, weth, usdc, amount, spotExecutor);

        EIP2098Permit memory signedPermit = env.dealAndPermit(weth, TRADER, TRADER_PK, amount, address(maestro));

        vm.prank(TRADER);
        maestro.swapAndDepositWithPermit(weth, usdc, swapData, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositWithPermit2() public {
        uint256 amount = 10 ether;

        SwapData memory swapData = _swap(router, weth, usdc, amount, spotExecutor);

        EIP2098Permit memory signedPermit = env.dealAndPermit2(weth, TRADER, TRADER_PK, amount, address(maestro));

        vm.prank(TRADER);
        maestro.swapAndDepositWithPermit2(weth, usdc, swapData, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testDepositValidations() public {
        // token not registered
        IERC20 arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548); // ARB on arbitrum

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, arb));
        vm.prank(TRADER);
        maestro.deposit(arb, 10_000e18);

        EIP2098Permit memory signedPermit = env.dealAndPermit(arb, TRADER, TRADER_PK, 10_000e18, address(vault));
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, arb));
        vm.prank(TRADER);
        maestro.depositWithPermit(arb, signedPermit, 0);

        signedPermit = env.dealAndPermit2(arb, TRADER, TRADER_PK, 10_000e18, address(maestro));
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, arb));
        vm.prank(TRADER);
        maestro.depositWithPermit2(arb, signedPermit, 0);
    }

    function testWithdraw_ExactAmount() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        maestro.withdraw(usdc, 10_000e6, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 10_000e6, "trader balance");
    }

    function testWithdraw_PartialAmount() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        snapStart("Maestro:Withdraw_PartialAmount");
        maestro.withdraw(usdc, 5000e6, TRADER);
        snapEnd();

        assertEq(vault.balanceOf(usdc, TRADER), 5000e6, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 5000e6, "trader balance");
    }

    function testWithdraw_All() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        maestro.withdraw(usdc, 0, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 10_000e6, "trader balance");
    }

    function testWithdrawNative_ExactAmount() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(10 ether, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testWithdrawNative_PartialAmount() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(5 ether, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 5 ether, "trader vault balance");
        assertEq(TRADER.balance, 5 ether, "trader balance");
    }

    function testWithdrawNative_All() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(0, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testSwapAndWithdraw() public {
        vm.deal(TRADER, 0);
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        uint256 amount = 10_000e6;
        vm.prank(TRADER);
        maestro.deposit(usdc, amount);

        SwapData memory swapData = _swap(router, usdc, weth, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndWithdraw(usdc, weth, swapData, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(weth.balanceOf(TRADER), 10 ether, "trader balance");
    }

    function testSwapAndWithdrawNative() public {
        vm.deal(TRADER, 0);
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        uint256 amount = 10_000e6;
        vm.prank(TRADER);
        maestro.deposit(usdc, amount);

        SwapData memory swapData = _swap(router, usdc, weth, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndWithdrawNative(usdc, swapData, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testTrade() public {
        env.dealAndApprove(usdc, TRADER, 4004e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4004e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        FeeParams memory feeParams = FeeParams({ token: usdc, amount: 4e6, basisPoints: 10 });

        vm.prank(TRADER);
        vm.expectEmit(true, true, true, true);
        emit FeeCollected(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000001),
            TRADER,
            TREASURY,
            feeParams.token,
            feeParams.amount,
            feeParams.basisPoints
        );
        (PositionId positionId,) = maestro.tradeWithFees(tradeParams, executionParams, feeParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(usdc.balanceOf(TREASURY), 4e6, "fees collected");
    }

    function testTradeWithBalance() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4000e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        tradeParams.cashflow = type(int256).max;

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.trade(tradeParams, executionParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testDepositAndTradeNative_multicallEdition() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Base, 4 ether);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IMaestro.depositNative.selector);
        data[1] = abi.encodeWithSelector(IMaestro.trade.selector, tradeParams, executionParams);

        vm.prank(TRADER);
        (bytes[] memory results) = maestro.multicall{ value: 4 ether }(data);

        PositionId positionId = abi.decode(results[1], (PositionId));

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testTradeAndLinkedOrder() public {
        env.dealAndApprove(usdc, TRADER, 4004e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4004e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        FeeParams memory feeParams = FeeParams({ token: usdc, amount: 4e6, basisPoints: 10 });

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        vm.expectEmit(true, true, true, true);
        emit FeeCollected(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000001),
            TRADER,
            TREASURY,
            feeParams.token,
            feeParams.amount,
            feeParams.basisPoints
        );
        (PositionId positionId,, OrderId linkedOrderId) =
            maestro.tradeAndLinkedOrderWithFees(tradeParams, executionParams, linkedOrderParams, feeParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        Order memory order = orderManager.orders(linkedOrderId);
        assertEq(order.owner, TRADER, "order owner");
        assertEq(PositionId.unwrap(order.positionId), PositionId.unwrap(positionId), "order positionId");
        assertEq(order.quantity, type(int128).min, "order quantity");
        assertEq(order.limitPrice, linkedOrderParams.limitPrice, "order limitPrice");
        assertEq(order.tolerance, linkedOrderParams.tolerance, "order tolerance");
        assertEq(order.cashflow, 0, "order cashflow");
        assertEq(uint8(order.cashflowCcy), uint8(linkedOrderParams.cashflowCcy), "order cashflowCcy");
        assertEq(order.deadline, linkedOrderParams.deadline, "order deadline");
        assertEq(uint8(order.orderType), uint8(linkedOrderParams.orderType), "order orderType");
        assertEq(usdc.balanceOf(TREASURY), 4e6, "fees collected");
    }

    function testTradeAndLinkedOrders() public {
        env.dealAndApprove(usdc, TRADER, 4004e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4004e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        FeeParams memory feeParams = FeeParams({ token: usdc, amount: 4e6, basisPoints: 10 });

        LinkedOrderParams memory takeProfit = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        LinkedOrderParams memory stopLoss = LinkedOrderParams({
            limitPrice: 900e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.prank(TRADER);
        vm.expectEmit(true, true, true, true);
        emit FeeCollected(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000001),
            TRADER,
            TREASURY,
            feeParams.token,
            feeParams.amount,
            feeParams.basisPoints
        );
        (PositionId positionId,, OrderId takeProfitOrderId, OrderId stopLossOrderId) =
            maestro.tradeAndLinkedOrdersWithFees(tradeParams, executionParams, takeProfit, stopLoss, feeParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(takeProfitOrderId).owner, TRADER, "tp owner");
        assertEq(orderManager.orders(stopLossOrderId).owner, TRADER, "sl owner");
        assertEq(usdc.balanceOf(TREASURY), 4e6, "fees collected");
    }

    function testPlaceLinkedOrder() public returns (PositionId positionId, OrderId orderId) {
        (, positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.placeLinkedOrder(positionId, linkedOrderParams);

        vm.prank(TRADER);
        orderId = maestro.placeLinkedOrder(positionId, linkedOrderParams);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
    }

    function testCancel() public {
        (, OrderId orderId) = testPlaceLinkedOrder();

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancel(orderId);

        vm.prank(TRADER);
        maestro.cancel(orderId);
        assertEq(orderManager.orders(orderId).owner, address(0), "order owner");
    }

    function _prepareCloseTrade(PositionId positionId, Currency cashflowCcy)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        return _prepareCloseTrade(10 ether, positionId, cashflowCcy);
    }

    function _prepareCloseTrade(uint256 quantity, PositionId positionId, Currency cashflowCcy)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        TSQuote memory quote = positionActions.quoteTrade({
            positionId: positionId,
            quantity: -int256(quantity),
            leverage: 0,
            cashflow: 0,
            cashflowCcy: cashflowCcy
        });

        tradeParams = quote.tradeParams;
        executionParams = quote.execParams;
    }

    function _prepareTrade(Currency cashflowCcy, int256 cashflow)
        internal
        returns (TradeParams memory tradeParams, ExecutionParams memory executionParams)
    {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        TSQuote memory quote =
            positionActions.quoteWithCashflow({ positionId: positionId, quantity: 10 ether, cashflow: cashflow, cashflowCcy: cashflowCcy });

        tradeParams = quote.tradeParams;
        executionParams = quote.execParams;
    }

    function testRoute() public {
        address validIntegration = address(new Integration());
        address invalidIntegration = address(new Integration());

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.setIntegration(validIntegration, true);

        vm.prank(TIMELOCK_ADDRESS);
        maestro.setIntegration(validIntegration, true);
        assertEq(maestro.isIntegration(validIntegration), true, "valid integration");

        vm.expectCall(validIntegration, abi.encodeWithSelector(Integration.foo.selector));
        maestro.route(validIntegration, 0, abi.encodeWithSelector(Integration.foo.selector));

        vm.expectRevert(abi.encodeWithSelector(IMaestro.UnknownIntegration.selector, invalidIntegration));
        maestro.route(invalidIntegration, 0, "");

        vm.prank(TIMELOCK_ADDRESS);
        maestro.setIntegration(validIntegration, false);
        assertEq(maestro.isIntegration(validIntegration), false, "now is invalid integration");

        vm.expectRevert(abi.encodeWithSelector(IMaestro.UnknownIntegration.selector, validIntegration));
        maestro.route(validIntegration, 0, "");
    }

    function testTransferPosition() public {
        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");

        vm.expectRevert("ERC721: transfer from incorrect owner");
        maestro.transferPosition(positionId, TRADER2, "");

        vm.prank(TRADER);
        maestro.transferPosition(positionId, TRADER2, "");

        assertEq(positionNFT.positionOwner(positionId), TRADER2, "new position owner");
    }

    function testTradeOnExistingPosition() public {
        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        env.dealAndApprove(usdc, TRADER, 4004e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4004e6);

        TSQuote memory quote =
            positionActions.quoteWithCashflow({ positionId: positionId, quantity: 10 ether, cashflow: 4000e6, cashflowCcy: Currency.Quote });
        FeeParams memory feeParams = FeeParams({ token: usdc, amount: 4e6, basisPoints: 10 });

        vm.prank(TRADER);
        vm.expectEmit(true, true, true, true);
        emit FeeCollected(positionId, TRADER, TREASURY, feeParams.token, feeParams.amount, feeParams.basisPoints);
        (positionId,) = maestro.tradeWithFees(quote.tradeParams, quote.execParams, feeParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(usdc.balanceOf(TREASURY), 4e6, "fees collected");
    }

}

contract Integration {

    function foo() external pure { }

}

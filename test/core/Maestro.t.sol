//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/models/FixedFeeModel.sol";

import "../BaseTest.sol";
import "forge-std/console.sol";

contract MaestroTest is BaseTest {

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
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
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

    function testDepositWithPermit() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 10_000e6, address(vault));

        vm.prank(TRADER);
        maestro.depositWithPermit(IERC20Permit(address(usdc)), signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testDepositWithPermit2() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit2(usdc, TRADER, TRADER_PK, 10_000e6, address(maestro));

        vm.prank(TRADER);
        maestro.depositWithPermit2(usdc, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function _swap(IERC20 from, IERC20 to, uint256 amount, address recipient) internal view returns (Swap memory) {
        return Swap({
            router: address(router),
            spender: address(router),
            swapAmount: amount,
            swapBytes: abi.encodeWithSelector(
                router.exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(address(from), uint24(500), address(to)),
                    recipient: recipient,
                    amountIn: amount,
                    amountOutMinimum: 0 // UI's problem
                 })
                )
        });
    }

    function testSwapAndDeposit() public {
        uint256 amount = 10 ether;
        env.dealAndApprove(weth, TRADER, amount, address(maestro));

        Swap memory swap = _swap(weth, usdc, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndDeposit(weth, usdc, swap);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositNative() public {
        uint256 amount = 10 ether;
        vm.deal(TRADER, amount);

        Swap memory swap = _swap(weth, usdc, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndDepositNative{ value: amount }(usdc, swap);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositWithPermit() public {
        uint256 amount = 10 ether;

        Swap memory swap = _swap(weth, usdc, amount, spotExecutor);

        EIP2098Permit memory signedPermit = env.dealAndPermit(weth, TRADER, TRADER_PK, amount, address(maestro));

        vm.prank(TRADER);
        maestro.swapAndDepositWithPermit(weth, usdc, swap, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 10_000e6, "trader vault balance");
    }

    function testSwapAndDepositWithPermit2() public {
        uint256 amount = 10 ether;

        Swap memory swap = _swap(weth, usdc, amount, spotExecutor);

        EIP2098Permit memory signedPermit = env.dealAndPermit2(weth, TRADER, TRADER_PK, amount, address(maestro));

        vm.prank(TRADER);
        maestro.swapAndDepositWithPermit2(weth, usdc, swap, signedPermit);

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
        maestro.depositWithPermit(IERC20Permit(address(arb)), signedPermit);

        signedPermit = env.dealAndPermit2(arb, TRADER, TRADER_PK, 10_000e18, address(maestro));
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, arb));
        vm.prank(TRADER);
        maestro.depositWithPermit2(arb, signedPermit);
    }

    function testWithdraw() public {
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 10_000e6);

        vm.prank(TRADER);
        maestro.withdraw(usdc, 10_000e6, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 10_000e6, "trader balance");
    }

    function testWithdrawNative() public {
        vm.deal(TRADER, 10 ether);
        vm.prank(TRADER);
        maestro.depositNative{ value: 10 ether }();

        vm.prank(TRADER);
        maestro.withdrawNative(10 ether, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testSwapAndWithdraw() public {
        vm.deal(TRADER, 0);
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        uint256 amount = 10_000e6;
        vm.prank(TRADER);
        maestro.deposit(usdc, amount);

        Swap memory swap = _swap(usdc, weth, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndWithdraw(usdc, weth, swap, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(weth.balanceOf(TRADER), 10 ether, "trader balance");
    }

    function testSwapAndWithdrawNative() public {
        vm.deal(TRADER, 0);
        env.dealAndApprove(usdc, TRADER, 10_000e6, address(vault));
        uint256 amount = 10_000e6;
        vm.prank(TRADER);
        maestro.deposit(usdc, amount);

        Swap memory swap = _swap(usdc, weth, amount, spotExecutor);

        vm.prank(TRADER);
        maestro.swapAndWithdrawNative(usdc, swap, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 10 ether, "trader balance");
    }

    function testTrade() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4000e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.trade(tradeParams, executionParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
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

    function testDepositAndTradeVanilla() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.depositAndTrade(tradeParams, executionParams);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testDepositAndTradeNative() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Base, 4 ether);

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.depositAndTrade{ value: 4 ether }(tradeParams, executionParams);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testDepositAndTradeNative_FailOnNonNativeToken() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4 ether);

        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(IMaestro.NotNativeToken.selector, usdc));
        maestro.depositAndTrade{ value: 4 ether }(tradeParams, executionParams);
    }

    function testDepositAndTradeWithPermit() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        vm.prank(TRADER);
        (PositionId positionId,) = maestro.depositAndTradeWithPermit(tradeParams, executionParams, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
    }

    function testDepositAndTradeWithPermit_FailOnInsufficientPermitAmount() public {
        uint256 cashflow = 4000e6;

        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, cashflow - 1, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, int256(cashflow));

        vm.expectRevert(abi.encodeWithSelector(IMaestro.InsufficientPermitAmount.selector, cashflow, cashflow - 1));
        vm.prank(TRADER);
        maestro.depositAndTradeWithPermit(tradeParams, executionParams, signedPermit);
    }

    function testTradeAndWithdraw() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        // decrease without cashflow without failing
        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareCloseTrade(1 ether, positionId, Currency.None);

        vm.prank(TRADER);
        maestro.tradeAndWithdraw(tradeParams, executionParams, TRADER);

        // fully close
        (tradeParams, executionParams) = _prepareCloseTrade(positionId, Currency.Quote);

        vm.prank(TRADER);
        (, Trade memory trade_,) = maestro.tradeAndWithdraw(tradeParams, executionParams, TRADER);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), trade_.cashflow.abs(), "trader balance");
    }

    function testTradeAndWithdrawNative() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        // decrease without cashflow without failing
        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareCloseTrade(1 ether, positionId, Currency.None);

        vm.prank(TRADER);
        maestro.tradeAndWithdrawNative(tradeParams, executionParams, TRADER);

        // fully close
        (tradeParams, executionParams) = _prepareCloseTrade(positionId, Currency.Base);

        vm.prank(TRADER);
        (, Trade memory trade_,) = maestro.tradeAndWithdrawNative(tradeParams, executionParams, TRADER);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertGt(TRADER.balance, trade_.cashflow.abs(), "trader balance");
    }

    function testTradeAndWithdraw_FailOnInvalidCashflow() public {
        positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        // increase with positive cashflow and try to withdraw

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);
        vm.expectRevert(IMaestro.InvalidCashflow.selector);
        vm.prank(TRADER);
        maestro.tradeAndWithdraw(tradeParams, executionParams, TRADER);

        (tradeParams, executionParams) = _prepareTrade(Currency.Base, 4 ether);
        vm.expectRevert(IMaestro.InvalidCashflow.selector);
        vm.prank(TRADER);
        maestro.tradeAndWithdrawNative(tradeParams, executionParams, TRADER);
    }

    function testTradeAndLinkedOrder() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4000e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        (PositionId positionId,, OrderId linkedOrderId) = maestro.tradeAndLinkedOrder(tradeParams, executionParams, linkedOrderParams);

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
    }

    function testTradeAndLinkedOrders() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));
        vm.prank(TRADER);
        maestro.deposit(usdc, 4000e6);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

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
        (PositionId positionId,, OrderId takeProfitOrderId, OrderId stopLossOrderId) =
            maestro.tradeAndLinkedOrders(tradeParams, executionParams, takeProfit, stopLoss);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(takeProfitOrderId).owner, TRADER, "tp owner");
        assertEq(orderManager.orders(stopLossOrderId).owner, TRADER, "sl owner");
    }

    function testDepositTradeAndLinkedOrder() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        (PositionId positionId,, OrderId linkedOrderId) =
            maestro.depositTradeAndLinkedOrder(tradeParams, executionParams, linkedOrderParams);

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
    }

    function testDepositTradeAndLinkedOrderNative() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Base, 4 ether);

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Base,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        (PositionId positionId,, OrderId linkedOrderId) =
            maestro.depositTradeAndLinkedOrder{ value: 4 ether }(tradeParams, executionParams, linkedOrderParams);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(linkedOrderId).owner, TRADER, "order owner");
    }

    function testDepositTradeAndLinkedOrderWithPermit() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

        LinkedOrderParams memory linkedOrderParams = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        (PositionId positionId,, OrderId linkedOrderId) =
            maestro.depositTradeAndLinkedOrderWithPermit(tradeParams, executionParams, linkedOrderParams, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(linkedOrderId).owner, TRADER, "order owner");
    }

    function testDepositTradeAndLinkedOrders() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

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
        (PositionId positionId,, OrderId takeProfitOrderId, OrderId stopLossOrderId) =
            maestro.depositTradeAndLinkedOrders(tradeParams, executionParams, takeProfit, stopLoss);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(takeProfitOrderId).owner, TRADER, "tp owner");
        assertEq(orderManager.orders(stopLossOrderId).owner, TRADER, "sl owner");
    }

    function testDepositTradeAndLinkedOrdersNative() public {
        vm.deal(TRADER, 4 ether);

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Base, 4 ether);

        LinkedOrderParams memory takeProfit = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Base,
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
        (PositionId positionId,, OrderId takeProfitOrderId, OrderId stopLossOrderId) =
            maestro.depositTradeAndLinkedOrders{ value: 4 ether }(tradeParams, executionParams, takeProfit, stopLoss);

        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(takeProfitOrderId).owner, TRADER, "tp owner");
        assertEq(orderManager.orders(stopLossOrderId).owner, TRADER, "sl owner");
    }

    function testDepositTradeAndLinkedOrdersWithPermit() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 4000e6, address(vault));

        (TradeParams memory tradeParams, ExecutionParams memory executionParams) = _prepareTrade(Currency.Quote, 4000e6);

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
        (PositionId positionId,, OrderId takeProfitOrderId, OrderId stopLossOrderId) =
            maestro.depositTradeAndLinkedOrdersWithPermit(tradeParams, executionParams, takeProfit, stopLoss, signedPermit);

        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(positionNFT.positionOwner(positionId), TRADER, "position owner");
        assertEq(orderManager.orders(takeProfitOrderId).owner, TRADER, "tp owner");
        assertEq(orderManager.orders(stopLossOrderId).owner, TRADER, "sl owner");
    }

    function testPlace() public {
        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.place(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
    }

    function testPlaceLinkedOrder() public {
        (, PositionId positionId,) = positionActions.openPosition({
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
        OrderId orderId = maestro.placeLinkedOrder(positionId, linkedOrderParams);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
    }

    function testPlaceLinkedOrders() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        LinkedOrderParams memory linkedOrderParams1 = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        LinkedOrderParams memory linkedOrderParams2 = LinkedOrderParams({
            limitPrice: 900e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.placeLinkedOrders(positionId, linkedOrderParams1, linkedOrderParams2);

        vm.prank(TRADER);
        (OrderId linkedOrderId1, OrderId linkedOrderId2) = maestro.placeLinkedOrders(positionId, linkedOrderParams1, linkedOrderParams2);
        assertEq(orderManager.orders(linkedOrderId1).owner, TRADER, "linkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, TRADER, "linkedOrder2 owner");
    }

    function testDepositAndPlace() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlace(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 4000e6, "trader vault balance");
    }

    function testDepositAndPlaceNative() public {
        vm.deal(TRADER, 4 ether);

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlace{ value: 4 ether }(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(weth, TRADER), 4 ether, "trader vault balance");
    }

    function testDepositAndPlaceWithPermit() public {
        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, 4000e6, address(vault));

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlaceWithPermit(params, signedPermit);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 4000e6, "trader vault balance");
    }

    function testDepositAndPlaceWithPermit_FailOnInsufficientPermitAmount() public {
        uint256 cashflow = 4000e6;

        EIP2098Permit memory signedPermit = env.dealAndPermit(usdc, TRADER, TRADER_PK, cashflow - 1, address(vault));

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: int128(int256(cashflow)),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.expectRevert(abi.encodeWithSelector(IMaestro.InsufficientPermitAmount.selector, cashflow, cashflow - 1));
        vm.prank(TRADER);
        maestro.depositAndPlaceWithPermit(params, signedPermit);
    }

    function testCancel() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlace(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 4000e6, "trader vault balance");

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancel(orderId);

        vm.prank(TRADER);
        maestro.cancel(orderId);
        assertEq(orderManager.orders(orderId).owner, address(0), "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 4000e6, "trader vault balance");
    }

    function testCancelMultipleOrders() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        LinkedOrderParams memory linkedOrderParams1 = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        LinkedOrderParams memory linkedOrderParams2 = LinkedOrderParams({
            limitPrice: 900e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.prank(TRADER);
        (OrderId linkedOrderId1, OrderId linkedOrderId2) = maestro.placeLinkedOrders(positionId, linkedOrderParams1, linkedOrderParams2);
        assertEq(orderManager.orders(linkedOrderId1).owner, TRADER, "linkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, TRADER, "linkedOrder2 owner");

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancel(linkedOrderId1, linkedOrderId2);

        vm.prank(TRADER);
        maestro.cancel(linkedOrderId1, linkedOrderId2);
        assertEq(orderManager.orders(linkedOrderId1).owner, address(0), "linkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, address(0), "linkedOrder2 owner");
    }

    function testCancelReplaceLinkedOrder() public {
        (, PositionId positionId,) = positionActions.openPosition({
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

        vm.prank(TRADER);
        OrderId linkedOrderId = maestro.placeLinkedOrder(positionId, linkedOrderParams);
        assertEq(orderManager.orders(linkedOrderId).owner, TRADER, "linkedOrder owner");

        LinkedOrderParams memory newLinkedOrderParams = LinkedOrderParams({
            limitPrice: 900e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancelReplaceLinkedOrder(linkedOrderId, newLinkedOrderParams);

        vm.prank(TRADER);
        OrderId newLinkedOrderId = maestro.cancelReplaceLinkedOrder(linkedOrderId, newLinkedOrderParams);
        assertEq(orderManager.orders(linkedOrderId).owner, address(0), "linkedOrder owner");
        assertEq(orderManager.orders(newLinkedOrderId).owner, TRADER, "newLinkedOrder owner");
    }

    function testCancelReplaceLinkedOrders() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });

        LinkedOrderParams memory linkedOrderParams1 = LinkedOrderParams({
            limitPrice: 1100e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        LinkedOrderParams memory linkedOrderParams2 = LinkedOrderParams({
            limitPrice: 900e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.prank(TRADER);
        (OrderId linkedOrderId1, OrderId linkedOrderId2) = maestro.placeLinkedOrders(positionId, linkedOrderParams1, linkedOrderParams2);
        assertEq(orderManager.orders(linkedOrderId1).owner, TRADER, "linkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, TRADER, "linkedOrder2 owner");

        LinkedOrderParams memory newLinkedOrderParams1 = LinkedOrderParams({
            limitPrice: 1200e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.TakeProfit
        });

        LinkedOrderParams memory newLinkedOrderParams2 = LinkedOrderParams({
            limitPrice: 800e6,
            tolerance: 0.01e4,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp + 1 days),
            orderType: OrderType.StopLoss
        });

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancelReplaceLinkedOrders(linkedOrderId1, linkedOrderId2, newLinkedOrderParams1, newLinkedOrderParams2);

        vm.prank(TRADER);
        (OrderId newLinkedOrderId1, OrderId newLinkedOrderId2) =
            maestro.cancelReplaceLinkedOrders(linkedOrderId1, linkedOrderId2, newLinkedOrderParams1, newLinkedOrderParams2);
        assertEq(orderManager.orders(linkedOrderId1).owner, address(0), "cancelledLinkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, address(0), "cancelledLinkedOrder2 owner");
        assertEq(orderManager.orders(newLinkedOrderId1).owner, TRADER, "newLinkedOrder1 owner");
        assertEq(orderManager.orders(newLinkedOrderId2).owner, TRADER, "newLinkedOrder2 owner");
    }

    function testCancelReplaceLinkedOrders_FailOnDifferentPositionIds() public {
        (, PositionId positionId1,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base
        });
        (, PositionId positionId2,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 9 ether,
            cashflow: 3 ether,
            cashflowCcy: Currency.Base
        });

        vm.prank(TRADER);
        OrderId linkedOrderId1 = maestro.placeLinkedOrder(
            positionId1,
            LinkedOrderParams({
                limitPrice: 1100e6,
                tolerance: 0.01e4,
                cashflowCcy: Currency.Quote,
                deadline: uint32(block.timestamp + 1 days),
                orderType: OrderType.TakeProfit
            })
        );

        vm.prank(TRADER);
        OrderId linkedOrderId2 = maestro.placeLinkedOrder(
            positionId2,
            LinkedOrderParams({
                limitPrice: 1100e6,
                tolerance: 0.01e4,
                cashflowCcy: Currency.Quote,
                deadline: uint32(block.timestamp + 1 days),
                orderType: OrderType.TakeProfit
            })
        );

        assertEq(orderManager.orders(linkedOrderId1).owner, TRADER, "linkedOrder1 owner");
        assertEq(orderManager.orders(linkedOrderId2).owner, TRADER, "linkedOrder2 owner");

        LinkedOrderParams memory emptyLinkedOrderParams;

        vm.expectRevert(abi.encodeWithSelector(IMaestro.MismatchingPositionId.selector, linkedOrderId1, linkedOrderId2));
        vm.prank(TRADER);
        maestro.cancelReplaceLinkedOrders(linkedOrderId1, linkedOrderId2, emptyLinkedOrderParams, emptyLinkedOrderParams);
    }

    function testCancelAndWithdraw() public {
        env.dealAndApprove(usdc, TRADER, 4000e6, address(vault));

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlace(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 4000e6, "trader vault balance");

        vm.prank(TRADER);
        maestro.cancelAndWithdraw(orderId, TRADER);
        assertEq(orderManager.orders(orderId).owner, address(0), "order owner");
        assertEq(vault.balanceOf(usdc, TRADER), 0, "trader vault balance");
        assertEq(usdc.balanceOf(TRADER), 4000e6, "trader balance");
    }

    function testCancelAndWithdrawNative() public {
        vm.deal(TRADER, 4 ether);

        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0),
            quantity: 10 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 4 ether,
            cashflowCcy: Currency.Base,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = maestro.depositAndPlace{ value: 4 ether }(params);
        assertEq(orderManager.orders(orderId).owner, TRADER, "order owner");
        assertEq(vault.balanceOf(weth, TRADER), 4 ether, "trader vault balance");

        vm.prank(TRADER);
        maestro.cancelAndWithdrawNative(orderId, TRADER);
        assertEq(orderManager.orders(orderId).owner, address(0), "order owner");
        assertEq(vault.balanceOf(weth, TRADER), 0, "trader vault balance");
        assertEq(TRADER.balance, 4 ether, "trader balance");
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

}

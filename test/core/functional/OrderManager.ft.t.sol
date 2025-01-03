//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";
import "../../utils.t.sol";
import "../../StorageUtils.t.sol";
import "src/core/OrderManager.sol";

contract OrderManagerFunctional is BaseTest, IOrderManagerEvents, IOrderManagerErrors, IContangoErrors {

    using { toOrderId } for OrderParams;
    using { first } for Vm.Log[];
    using SignedMath for *;
    using SafeCast for *;
    using Math for *;
    using SignedMath for *;
    using Address for address payable;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    Contango internal contango;
    PositionNFT internal positionNFT;
    Maestro internal maestro;
    IOrderManager internal om;
    IVault internal vault;
    PositionActions internal positionActions;
    IERC20 internal usdc;

    address internal keeper = address(0xb07);
    address internal uniswap;

    // IMPORTANT: Never change this number, if the slots move cause we add mixins or whatever, discount the gap on the prod contract
    uint256 internal constant GAP = 50_000;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        mm = MM_AAVE;
        usdc = env.token(USDC);
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        contango = env.contango();
        positionActions = env.positionActions();
        positionNFT = contango.positionNFT();
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);

        om = env.orderManager();
        vault = env.vault();
        maestro = env.maestro();
        uniswap = env.uniswap();

        vm.prank(TIMELOCK_ADDRESS);
        OrderManager(address(om)).grantRole(BOT_ROLE, keeper);

        vm.prank(TIMELOCK_ADDRESS);
        OrderManager(address(om)).grantRole(OPERATOR_ROLE, TIMELOCK_ADDRESS);

        // Sets block.basefee
        vm.fee(1.5e9); // 1.5 gwei
        // Sets tx.gasprice
        vm.txGasPrice(1.7e9); // implicit tip of 0.2 gwei
    }

    // slot complexity:
    //  if flat, will be bytes32(uint256(uint));
    //  if map, will be keccak256(abi.encode(key, uint(slot)));
    //  if deep map, will be keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))));
    //  if map struct, will be bytes32(uint256(keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))))) + structFieldDepth);
    function testStorage() public {
        StorageUtils su = new StorageUtils(address(om));

        vm.startPrank(TIMELOCK_ADDRESS);
        om.setGasMultiplier(3e4);
        om.setGasTip(3e9);
        vm.stopPrank();

        uint256 slot0 = su.read_uint(bytes32(uint256(GAP)));
        assertEq(uint128(uint128(slot0)), 21_000, "gasStart");
        assertEq(uint64(slot0 >> 128), 3e4, "gasMultiplier");
        assertEq(uint64(slot0 >> 192), 3e9, "gasTip");

        assertEq(su.read_address(bytes32(uint256(GAP + 1))), address(env.contangoLens()), "oracle");

        // ================ Order storage ==================

        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: -5 ether,
            limitPrice: 1000e6,
            tolerance: 0.001e4,
            cashflow: -2000e6,
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);

        assertEq(
            su.read_bytes32(bytes32(uint256(keccak256(abi.encode(orderId, GAP + 2))) + 0)), PositionId.unwrap(positionId), "PositionId"
        );

        uint256 quantityAndPrice = su.read_uint(bytes32(uint256(keccak256(abi.encode(orderId, GAP + 2))) + 1));
        assertEq(int128(int256(quantityAndPrice)), params.quantity, "quantity");
        assertEq(quantityAndPrice >> 128, params.limitPrice, "limitPrice");

        uint256 triggerAndCashflow = su.read_uint(bytes32(uint256(keccak256(abi.encode(orderId, GAP + 2))) + 2));
        assertEq(uint128(uint256(triggerAndCashflow)), params.tolerance, "tolerance");
        assertEq(int128(int256(triggerAndCashflow >> 128)), params.cashflow, "cashflow");

        uint256 others = su.read_uint(bytes32(uint256(keccak256(abi.encode(orderId, GAP + 2))) + 3));
        assertEq(uint8(others), uint8(params.cashflowCcy), "cashflowCcy");
        assertEq(uint32(others >> 8), params.deadline, "deadline");
        assertEq(uint8(others >> 32 + 8), uint8(params.orderType), "orderType");
        assertEq(address(uint160(others >> 8 + 32 + 8)), TRADER, "owner");
    }

    function _testOpenPosition_HP() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        TSQuote memory quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 10 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        env.deposit(instrument.quote, TRADER, quote.cashflowUsed.toUint256() * 1.001e3 / 1e3);

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1001e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");
        assertEq(om.orders(orderId).owner, TRADER, "order owner");

        Trade memory trade;
        uint256 keeperReward;
        vm.recordLogs();
        vm.prank(keeper);
        (positionId, trade, keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertEq(positionNFT.positionOwner(positionId), TRADER, "positionOwner");
        assertApproxEqRelDecimal(
            trade.quantity, quote.quantity, DEFAULT_SLIPPAGE_TOLERANCE * 1e14, instrument.baseDecimals, "trade.quantity"
        );

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    function testIncreasePosition_HP() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 4 ether,
            leverage: 0,
            cashflow: 3000e6,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        env.deposit(instrument.quote, TRADER, quote.cashflowUsed.toUint256() * 1.001e3 / 1e3);

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1001e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");
        assertEq(om.orders(orderId).owner, TRADER, "order owner");

        Trade memory trade;
        uint256 keeperReward;
        vm.recordLogs();
        vm.prank(keeper);
        (positionId, trade, keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertApproxEqRelDecimal(trade.quantity, 4 ether, DEFAULT_SLIPPAGE_TOLERANCE * 1e14, instrument.baseDecimals, "trade.quantity");

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    function testDecreasePosition_HP() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 seconds);

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -4 ether,
            leverage: 0,
            cashflow: -3000e6,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");
        assertEq(om.orders(orderId).owner, TRADER, "order owner");

        vm.recordLogs();
        vm.prank(keeper);
        (, Trade memory trade, uint256 keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertApproxEqRelDecimal(trade.quantity, -4 ether, DEFAULT_SLIPPAGE_TOLERANCE * 1e14, instrument.baseDecimals, "trade.quantity");
        assertEqDecimal(
            instrument.quote.balanceOf(TRADER), quote.cashflowUsed.abs() - keeperReward, instrument.quoteDecimals, "trader balance"
        );

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    function testClosePosition_HP() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 seconds);

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -10 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            limitPrice: 1000e6,
            tolerance: 0,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        FeeParams memory feeParams = FeeParams({ token: usdc, amount: 4e6, basisPoints: 10 });

        vm.recordLogs();
        vm.prank(keeper);
        vm.expectEmit(true, true, true, true);
        emit FeeCollected(orderId, positionId, TRADER, TREASURY, feeParams.token, feeParams.amount, feeParams.basisPoints);
        (, Trade memory trade, uint256 keeperReward) = om.executeWithFees(orderId, quote.execParams, feeParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");
        assertLtDecimal(trade.quantity, -10 ether, instrument.baseDecimals, "trade.quantity");
        assertApproxEqRelDecimal(instrument.quote.balanceOf(TRADER), 3980e6, 0.01e18, instrument.quoteDecimals, "trader balance");

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");

        assertEq(usdc.balanceOf(TREASURY), 4e6, "fees collected");
    }

    function testCancel_HP() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        TSQuote memory quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 10 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        vm.prank(TRADER);
        maestro.cancel(orderId);
        assertFalse(om.hasOrder(orderId), "order removed");
    }

    function testTakeProfit_HP() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 seconds);

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -10 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            limitPrice: 1100e6,
            tolerance: 0,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        vm.prank(keeper);
        (bool success, bytes memory data) = address(om).call(abi.encodeWithSelector(om.execute.selector, orderId, quote.execParams));

        require(!success, "should have failed");
        require(bytes4(data) == PriceBelowLimit.selector, "error selector not expected");
        assertTrue(om.hasOrder(orderId), "order not removed");

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1101e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        vm.recordLogs();
        vm.prank(keeper);
        (, Trade memory trade, uint256 keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");
        assertLtDecimal(trade.quantity, -10 ether, instrument.baseDecimals, "trade.quantity");
        assertApproxEqRelDecimal(instrument.quote.balanceOf(TRADER), 4980e6, 0.01e18, instrument.quoteDecimals, "trader balance");

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    function testStopLoss_HP_CashflowQuote() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 seconds);

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -10 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            limitPrice: 899e6,
            tolerance: 0.001e4,
            deadline: uint32(block.timestamp),
            orderType: OrderType.StopLoss
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        vm.expectRevert(abi.encodePacked(IOrderManagerErrors.InvalidPrice.selector, uint256(1000e6), uint256(899e6)));
        vm.prank(keeper);
        om.execute(orderId, quote.execParams);
        assertTrue(om.hasOrder(orderId), "order not removed");

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 899e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        vm.recordLogs();
        vm.prank(keeper);
        (, Trade memory trade, uint256 keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");
        assertLtDecimal(trade.quantity, -10 ether, instrument.baseDecimals, "trade.quantity");
        assertApproxEqRelDecimal(instrument.quote.balanceOf(TRADER), 3000e6, 0.01e18, instrument.quoteDecimals, "trader balance");

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(instrument.quote.balanceOf(keeper), keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    function testStopLoss_HP_CashflowBase() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        skip(1 seconds);

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -10 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.Base,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.Base,
            limitPrice: 899e6,
            tolerance: 0.001e4,
            deadline: uint32(block.timestamp),
            orderType: OrderType.StopLoss
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        vm.expectRevert(abi.encodePacked(IOrderManagerErrors.InvalidPrice.selector, uint256(1000e6), uint256(899e6)));
        vm.prank(keeper);
        om.execute(orderId, quote.execParams);
        assertTrue(om.hasOrder(orderId), "order not removed");

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 899e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: -10 ether,
            leverage: 0,
            cashflow: 0,
            cashflowCcy: Currency.Base,
            slippageTolerance: 0
        });

        vm.recordLogs();
        vm.prank(keeper);
        (, Trade memory trade, uint256 keeperReward) = om.execute(orderId, quote.execParams);

        _assertOrderExecutedEvent(orderId, positionId, keeperReward);
        assertFalse(om.hasOrder(orderId), "order removed");

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");
        assertLtDecimal(trade.quantity, -10 ether, instrument.baseDecimals, "trade.quantity");
        assertApproxEqRelDecimal(TRADER.balance, 3.325 ether, 0.01e18, instrument.baseDecimals, "trader balance");

        assertGt(keeperReward, 0, "keeper reward");
        assertEqDecimal(keeper.balance, keeperReward, instrument.quoteDecimals, "keeper balance");
    }

    // Can't place an order with invalid symbol
    function testPlace_Validation01() public {
        Symbol invalidSymbol = Symbol.wrap("");
        PositionId positionId = env.encoder().encodePositionId(invalidSymbol, mm, PERP, 0);

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: 0,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.expectRevert(abi.encodeWithSelector(InvalidInstrument.selector, invalidSymbol));

        om.place(params);
    }

    // Can't place an order with invalid money market
    function testPlace_Validation02() public {
        // manually created to go over type system
        // symbol: WETHUSDC
        // money market: invalid -> ff: 255
        // expiry: 0
        // number: 0
        PositionId positionId = PositionId.wrap(0x57455448555344430000000000000000ff000000000000000000000000000000);

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: 0,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.expectRevert(abi.encodeWithSelector(UnderlyingPositionFactory.InvalidMoneyMarket.selector, 255));
        om.place(params);
    }

    // Can't place an open order that has quantity 0
    function testPlace_Validation03() public {
        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0),
            quantity: 0,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.expectRevert(IOrderManagerErrors.InvalidQuantity.selector);

        om.place(params);
    }

    // Can't place an open order that is not a Limit order type
    function testPlace_Validation04() public {
        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0),
            quantity: 1 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.InvalidOrderType.selector, OrderType.TakeProfit));
        om.place(params);

        params.orderType = OrderType.StopLoss;
        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.InvalidOrderType.selector, OrderType.StopLoss));
        om.place(params);
    }

    // Can't place open order to increase position that is not type Limit
    function testPlace_Validation05() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: 1 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.TakeProfit
        });

        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.InvalidOrderType.selector, OrderType.TakeProfit));
        vm.prank(TRADER);
        om.place(params);

        params.orderType = OrderType.StopLoss;
        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.InvalidOrderType.selector, OrderType.StopLoss));
        vm.prank(TRADER);
        om.place(params);
    }

    // Can't place decrease position order with Limit type
    function testPlace_Validation06() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: -1 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.InvalidOrderType.selector, params.orderType));

        vm.prank(TRADER);
        om.place(params);
    }

    // Can't place an order for someone else's account
    function testPlace_Validation07() public {
        OrderParams memory params;

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        om.placeOnBehalfOf(params, address(1));
    }

    // Can't place and order on a position without approval
    function testPlace_Validation08() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params;
        params.positionId = positionId;

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        om.place(params);

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        om.place(params);
    }

    // Can't place an order twice
    function testPlace_Validation09() public {
        OrderParams memory params = OrderParams({
            positionId: env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0),
            quantity: 1 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);

        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.OrderAlreadyExists.selector, orderId));
        om.place(params);
    }

    // Can't place an order for a position that doesn't exist
    function testPlace_Validation10() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 1);

        OrderParams memory params;
        params.positionId = positionId;

        vm.expectRevert("ERC721: invalid token ID");

        vm.prank(TRADER);
        om.place(params);
    }

    // Can't place an order to fully close a position with cashflow currency set to None
    function testPlace_Validation11() public {
        (, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.None,
            limitPrice: 0,
            tolerance: 0,
            deadline: uint32(block.timestamp),
            orderType: OrderType.StopLoss
        });

        vm.expectRevert(abi.encodeWithSelector(CashflowCcyRequired.selector));
        vm.prank(TRADER);
        om.place(params);
    }

    // Can't place an order to fully close a position with tolerance higher than 1e4
    function testPlace_Validation12() public {
        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: type(int128).min,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            limitPrice: 0,
            tolerance: 1.0001e4,
            deadline: uint32(block.timestamp),
            orderType: OrderType.StopLoss
        });

        vm.expectRevert(abi.encodeWithSelector(InvalidTolerance.selector, 1.0001e4));

        vm.prank(TRADER);
        om.place(params);
    }

    // Can't cancel an order that does not exist
    function testCancel_Validation1() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        TSQuote memory quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 10 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        OrderId orderId = params.toOrderId();
        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.OrderDoesNotExist.selector, orderId));

        vm.prank(TRADER);
        om.cancel(orderId);
    }

    // Can't cancel an order without approval
    function testCancel_Validation2() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        TSQuote memory quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 10 ether,
            leverage: 2e18,
            cashflow: 0,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.cancel(orderId);

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        om.cancel(orderId);
    }

    // Can't trade with an expired order
    function testTrade_Validation1() public {
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: 1 ether,
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: 0,
            cashflowCcy: Currency.None,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        skip(1 seconds);

        vm.expectRevert(
            abi.encodeWithSelector(IOrderManagerErrors.OrderExpired.selector, orderId, params.deadline, uint32(block.timestamp))
        );
        vm.prank(keeper);
        om.execute(
            orderId,
            ExecutionParams({ router: uniswap, spender: uniswap, swapAmount: 0, swapBytes: "", flashLoanProvider: IERC7399(address(0)) })
        );
    }

    // Can't trade if position was transferred
    function testTrade_Validation2() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 4 ether,
            leverage: 0,
            cashflow: 3000e6,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        ExecutionParams memory execParams;

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.startPrank(TRADER);

        OrderId orderId = om.place(params);
        env.contango().positionNFT().safeTransferFrom(TRADER, address(0xdead), uint256(PositionId.unwrap(positionId)));

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IOrderManagerErrors.OrderInvalidated.selector, orderId));
        vm.prank(keeper);
        om.execute(orderId, execParams);
    }

    // Can't trade on a position that doesn't exist anymore
    function testTrade_Validation3() public {
        (TSQuote memory quote, PositionId positionId,) = positionActions.openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        quote = env.tsQuoter().quote({
            positionId: positionId,
            quantity: 4 ether,
            leverage: 0,
            cashflow: 3000e6,
            cashflowCcy: Currency.Quote,
            slippageTolerance: 0
        });

        env.dealAndApprove(instrument.quote, TRADER, quote.cashflowUsed.toUint256(), address(vault));

        OrderParams memory params = OrderParams({
            positionId: positionId,
            quantity: quote.quantity.toInt128(),
            limitPrice: 1000e6,
            tolerance: 0,
            cashflow: quote.cashflowUsed.toInt128(),
            cashflowCcy: Currency.Quote,
            deadline: uint32(block.timestamp),
            orderType: OrderType.Limit
        });

        vm.prank(TRADER);
        OrderId orderId = om.place(params);
        assertTrue(om.hasOrder(orderId), "order placed");

        // close position externally
        env.positionActions().closePosition({
            positionId: positionId,
            quantity: type(int128).max.toUint256(), // fully close
            cashflow: 0,
            cashflowCcy: Currency.Quote
        });

        assertFalse(env.contango().positionNFT().exists(positionId), "position exists");

        vm.expectRevert("ERC721: invalid token ID");
        vm.prank(keeper);
        om.execute(orderId, quote.execParams);

        assertTrue(om.hasOrder(orderId), "order not removed"); // garbage left behind
    }

    function testSetGasMultiplier() public {
        expectAccessControl(address(this), OPERATOR_ROLE);
        om.setGasMultiplier(1e4);

        vm.expectRevert(abi.encodeWithSelector(AboveMaxGasMultiplier.selector, 11e4));
        vm.prank(TIMELOCK_ADDRESS);
        om.setGasMultiplier(11e4);

        vm.expectRevert(abi.encodeWithSelector(BelowMinGasMultiplier.selector, 0.9e4));
        vm.prank(TIMELOCK_ADDRESS);
        om.setGasMultiplier(0.9e4);

        vm.expectEmit(true, true, true, true);
        emit GasMultiplierSet(5e4);
        vm.prank(TIMELOCK_ADDRESS);
        om.setGasMultiplier(5e4);
    }

    function testSetGasTip() public {
        expectAccessControl(address(this), OPERATOR_ROLE);
        om.setGasTip(1);

        vm.expectEmit(true, true, true, true);
        emit GasTipSet(3e9);
        vm.prank(TIMELOCK_ADDRESS);
        om.setGasTip(3e9);
    }

    function testTradePermissions() public {
        expectAccessControl(address(this), BOT_ROLE);
        om.execute(
            OrderId.wrap(""),
            ExecutionParams({
                router: address(0),
                spender: address(0),
                swapAmount: 0,
                swapBytes: "",
                flashLoanProvider: IERC7399(address(0))
            })
        );
    }

    function _assertOrderExecutedEvent(OrderId orderId, PositionId positionId, uint256 keeperReward) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory log = logs.first("OrderExecuted(bytes32,bytes32,uint256)");
        assertEq(log.topics[1], OrderId.unwrap(orderId), "OrderExecuted.orderId");
        assertEq(log.topics[2], PositionId.unwrap(positionId), "OrderExecuted.positionId");
        assertEq(log.data, abi.encode(keeperReward), "OrderExecuted.keeperReward");
    }

}

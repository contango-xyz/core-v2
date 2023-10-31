//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IPermit2 } from "../dependencies/Uniswap.sol";

import "../interfaces/IMaestro.sol";
import "../interfaces/IContango.sol";
import "../interfaces/IOrderManager.sol";
import "../interfaces/IVault.sol";
import "../libraries/Errors.sol";
import "../libraries/Validations.sol";
import "../libraries/ERC20Lib.sol";
import "../utils/SimpleSpotExecutor.sol";

contract Maestro is IMaestro, UUPSUpgradeable, Multicall {

    using SignedMath for int256;
    using SafeCast for *;
    using SafeERC20 for IERC20Permit;
    using ERC20Lib for *;
    using { validateCreatePositionPermissions, validateModifyPositionPermissions } for PositionNFT;

    bytes32 public constant UPPER_BIT_MASK = (0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    Timelock public immutable timelock;
    IContango public immutable contango;
    IOrderManager public immutable orderManager;
    IVault public immutable vault;
    PositionNFT public immutable positionNFT;
    IWETH9 public immutable nativeToken;
    IPermit2 public immutable permit2;
    SimpleSpotExecutor public immutable spotExecutor;

    constructor(
        Timelock _timelock,
        IContango _contango,
        IOrderManager _orderManager,
        IVault _vault,
        IPermit2 _permit2,
        SimpleSpotExecutor _spotExecutor
    ) {
        timelock = _timelock;
        contango = _contango;
        orderManager = _orderManager;
        vault = _vault;
        permit2 = _permit2;
        spotExecutor = _spotExecutor;
        positionNFT = _contango.positionNFT();
        nativeToken = _vault.nativeToken();
    }

    function deposit(IERC20 token, uint256 amount) public override returns (uint256) {
        return vault.deposit(token, msg.sender, amount);
    }

    function depositNative() public payable returns (uint256) {
        return vault.depositNative{ value: msg.value }(msg.sender);
    }

    function applyPermit(IERC20Permit token, EIP2098Permit calldata permit, address spender) public {
        // Inspired by https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol
        token.safePermit({
            owner: msg.sender,
            spender: spender,
            value: permit.amount,
            deadline: permit.deadline,
            r: permit.r,
            v: uint8(uint256(permit.vs >> 255)) + 27,
            s: permit.vs & UPPER_BIT_MASK
        });
    }

    function depositWithPermit(IERC20Permit token, EIP2098Permit calldata permit) public override returns (uint256) {
        applyPermit(token, permit, address(vault));
        return deposit(IERC20(address(token)), permit.amount);
    }

    function usePermit2(IERC20 token, EIP2098Permit calldata permit, address to) public {
        address sender = msg.sender;
        permit2.permitTransferFrom({
            permit: IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({ token: address(token), amount: permit.amount }),
                nonce: uint256(keccak256(abi.encode(sender, token, permit.amount, permit.deadline))),
                deadline: permit.deadline
            }),
            transferDetails: IPermit2.SignatureTransferDetails({ to: to, requestedAmount: permit.amount }),
            owner: sender,
            signature: abi.encodePacked(permit.r, permit.vs)
        });
    }

    function depositWithPermit2(IERC20 token, EIP2098Permit calldata permit) public override returns (uint256) {
        usePermit2(token, permit, address(vault));
        return deposit(token, permit.amount);
    }

    function _swapAndDeposit(address payer, IERC20 tokenToSell, IERC20 tokenToDeposit, Swap calldata swap) internal returns (uint256) {
        if (payer != address(0)) tokenToSell.transferOut(payer, address(spotExecutor), swap.swapAmount);
        uint256 output = spotExecutor.executeSwap(tokenToSell, tokenToDeposit, swap, address(vault));
        return deposit(tokenToDeposit, output);
    }

    function swapAndDeposit(IERC20 tokenToSell, IERC20 tokenToDeposit, Swap calldata swap) public override returns (uint256) {
        return _swapAndDeposit(msg.sender, tokenToSell, tokenToDeposit, swap);
    }

    function swapAndDepositNative(IERC20 tokenToDeposit, Swap calldata swap) public payable override returns (uint256) {
        nativeToken.deposit{ value: msg.value }();
        return _swapAndDeposit(address(this), nativeToken, tokenToDeposit, swap);
    }

    function swapAndDepositWithPermit(IERC20 tokenToSell, IERC20 tokenToDeposit, Swap calldata swap, EIP2098Permit calldata permit)
        public
        override
        returns (uint256)
    {
        applyPermit(IERC20Permit(address(tokenToSell)), permit, address(this));
        return _swapAndDeposit(msg.sender, tokenToSell, tokenToDeposit, swap);
    }

    function swapAndDepositWithPermit2(IERC20 tokenToSell, IERC20 tokenToDeposit, Swap calldata swap, EIP2098Permit calldata permit)
        public
        override
        returns (uint256)
    {
        usePermit2(tokenToSell, permit, address(spotExecutor));
        return _swapAndDeposit(address(0), tokenToSell, tokenToDeposit, swap);
    }

    function withdraw(IERC20 token, uint256 amount, address to) public override returns (uint256) {
        return vault.withdraw(token, msg.sender, amount, to);
    }

    function withdrawNative(uint256 amount, address to) public override returns (uint256) {
        return vault.withdrawNative(msg.sender, amount, to);
    }

    function swapAndWithdraw(IERC20 tokenToSell, IERC20 tokenToReceive, Swap calldata swap, address to) public returns (uint256) {
        withdraw(tokenToSell, swap.swapAmount, address(spotExecutor));
        return spotExecutor.executeSwap(tokenToSell, tokenToReceive, swap, to);
    }

    function swapAndWithdrawNative(IERC20 tokenToSell, Swap calldata swap, address payable to) public returns (uint256 output) {
        withdraw(tokenToSell, swap.swapAmount, address(spotExecutor));
        output = spotExecutor.executeSwap(tokenToSell, nativeToken, swap, address(this));
        nativeToken.transferOutNative(to, output);
    }

    function trade(TradeParams memory tradeParams, ExecutionParams calldata execParams) public returns (PositionId, Trade memory) {
        if (positionNFT.exists(tradeParams.positionId)) positionNFT.validateModifyPositionPermissions(tradeParams.positionId);
        if (tradeParams.cashflow == type(int256).max) {
            tradeParams.cashflow = vault.balanceOf(_cashflowToken(tradeParams), msg.sender).toInt256();
        }
        return contango.tradeOnBehalfOf(tradeParams, execParams, msg.sender);
    }

    function depositAndTrade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        public
        payable
        returns (PositionId, Trade memory)
    {
        _deposit(_cashflowToken(tradeParams), tradeParams.cashflow.toUint256());
        return trade(tradeParams, execParams);
    }

    function depositAndTradeWithPermit(TradeParams calldata tradeParams, ExecutionParams calldata execParams, EIP2098Permit calldata permit)
        public
        override
        returns (PositionId, Trade memory)
    {
        _validatePermitAmount(tradeParams.cashflow, permit);
        depositWithPermit(IERC20Permit(address(_cashflowToken(tradeParams))), permit);
        return trade(tradeParams, execParams);
    }

    function tradeAndWithdraw(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
        public
        returns (PositionId positionId, Trade memory trade_, uint256 amount)
    {
        return _tradeAndWithdraw(tradeParams, execParams, to, false);
    }

    function tradeAndWithdrawNative(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
        public
        returns (PositionId positionId, Trade memory trade_, uint256 amount)
    {
        return _tradeAndWithdraw(tradeParams, execParams, to, true);
    }

    function _tradeAndWithdraw(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to, bool native)
        public
        returns (PositionId positionId, Trade memory trade_, uint256 amount)
    {
        if (tradeParams.cashflow > 0) revert InvalidCashflow();

        (positionId, trade_) = trade(tradeParams, execParams);
        // avoid reverting on vault if actual trade cashflow is not negative
        if (trade_.cashflow < 0) {
            amount = trade_.cashflow.abs();

            Instrument memory instrument = contango.instrument(positionId.getSymbol());
            IERC20 cashflowToken = trade_.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;

            if (native) {
                if (nativeToken != cashflowToken) revert NotNativeToken(cashflowToken);
                withdrawNative(amount, to);
            } else {
                withdraw(cashflowToken, amount, to);
            }
        }
    }

    function tradeAndLinkedOrder(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
        (positionId, trade_) = trade(tradeParams, execParams);
        linkedOrderId = placeLinkedOrder(positionId, linkedOrderParams);
    }

    function tradeAndLinkedOrders(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2) {
        (positionId, trade_) = trade(tradeParams, execParams);
        linkedOrderId1 = placeLinkedOrder(positionId, linkedOrderParams1);
        linkedOrderId2 = placeLinkedOrder(positionId, linkedOrderParams2);
    }

    function depositTradeAndLinkedOrder(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams
    ) public payable override returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
        (positionId, trade_) = depositAndTrade(tradeParams, execParams);
        linkedOrderId = placeLinkedOrder(positionId, linkedOrderParams);
    }

    function depositTradeAndLinkedOrderWithPermit(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams,
        EIP2098Permit calldata permit
    ) public override returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
        (positionId, trade_) = depositAndTradeWithPermit(tradeParams, execParams, permit);
        linkedOrderId = placeLinkedOrder(positionId, linkedOrderParams);
    }

    function depositTradeAndLinkedOrders(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) public payable override returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2) {
        (positionId, trade_) = depositAndTrade(tradeParams, execParams);
        linkedOrderId1 = placeLinkedOrder(positionId, linkedOrderParams1);
        linkedOrderId2 = placeLinkedOrder(positionId, linkedOrderParams2);
    }

    function depositTradeAndLinkedOrdersWithPermit(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2,
        EIP2098Permit calldata permit
    ) public override returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2) {
        (positionId, trade_) = depositAndTradeWithPermit(tradeParams, execParams, permit);
        linkedOrderId1 = placeLinkedOrder(positionId, linkedOrderParams1);
        linkedOrderId2 = placeLinkedOrder(positionId, linkedOrderParams2);
    }

    function place(OrderParams memory params) public override returns (OrderId orderId) {
        if (positionNFT.exists(params.positionId)) positionNFT.validateModifyPositionPermissions(params.positionId);

        return orderManager.placeOnBehalfOf(params, msg.sender);
    }

    function placeLinkedOrder(PositionId positionId, LinkedOrderParams memory params) public override returns (OrderId orderId) {
        positionNFT.validateModifyPositionPermissions(positionId);
        orderId = _placeLinkedOrder(positionId, params);
    }

    function placeLinkedOrders(
        PositionId positionId,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) public override returns (OrderId linkedOrderId1, OrderId linkedOrderId2) {
        positionNFT.validateModifyPositionPermissions(positionId);
        linkedOrderId1 = _placeLinkedOrder(positionId, linkedOrderParams1);
        linkedOrderId2 = _placeLinkedOrder(positionId, linkedOrderParams2);
    }

    function _placeLinkedOrder(PositionId positionId, LinkedOrderParams memory params) private returns (OrderId orderId) {
        return orderManager.placeOnBehalfOf(
            OrderParams({
                positionId: positionId,
                quantity: type(int128).min,
                limitPrice: params.limitPrice,
                tolerance: params.tolerance,
                cashflow: 0,
                cashflowCcy: params.cashflowCcy,
                deadline: params.deadline,
                orderType: params.orderType
            }),
            msg.sender
        );
    }

    function depositAndPlace(OrderParams memory params) public payable override returns (OrderId orderId) {
        Instrument memory instrument = contango.instrument(params.positionId.getSymbol());
        IERC20 cashflowToken = params.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
        _deposit(cashflowToken, int256(params.cashflow).toUint256());
        return place(params);
    }

    function depositAndPlaceWithPermit(OrderParams memory params, EIP2098Permit calldata permit) public returns (OrderId orderId) {
        _validatePermitAmount(params.cashflow, permit);

        Instrument memory instrument = contango.instrument(params.positionId.getSymbol());
        IERC20Permit cashflowToken = IERC20Permit(address(params.cashflowCcy == Currency.Base ? instrument.base : instrument.quote));

        depositWithPermit(cashflowToken, permit);
        return place(params);
    }

    function cancel(OrderId orderId) public {
        if (!positionNFT.isApprovedForAll(orderManager.orders(orderId).owner, msg.sender)) revert Unauthorised(msg.sender);
        orderManager.cancel(orderId);
    }

    function cancel(OrderId orderId1, OrderId orderId2) public override {
        cancel(orderId1);
        cancel(orderId2);
    }

    function cancelReplaceLinkedOrder(OrderId cancelOrderId, LinkedOrderParams memory newLinkedOrderParams)
        external
        override
        returns (OrderId newLinkedOrderId)
    {
        PositionId positionId = orderManager.orders(cancelOrderId).positionId;
        cancel(cancelOrderId);
        return placeLinkedOrder(positionId, newLinkedOrderParams);
    }

    function cancelReplaceLinkedOrders(
        OrderId cancelOrderId1,
        OrderId cancelOrderId2,
        LinkedOrderParams memory newLinkedOrderParams1,
        LinkedOrderParams memory newLinkedOrderParams2
    ) external override returns (OrderId newLinkedOrderId1, OrderId newLinkedOrderId2) {
        PositionId positionId = orderManager.orders(cancelOrderId1).positionId;
        if (PositionId.unwrap(positionId) != PositionId.unwrap(orderManager.orders(cancelOrderId2).positionId)) {
            revert MismatchingPositionId(cancelOrderId1, cancelOrderId2);
        }

        cancel(cancelOrderId1, cancelOrderId2);
        (newLinkedOrderId1, newLinkedOrderId2) = placeLinkedOrders(positionId, newLinkedOrderParams1, newLinkedOrderParams2);
    }

    function cancelAndWithdraw(OrderId orderId, address to) public override returns (uint256) {
        Order memory order = orderManager.orders(orderId);
        cancel(orderId);
        Instrument memory instrument = contango.instrument(order.positionId.getSymbol());
        IERC20 cashflowToken = order.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
        return withdraw(cashflowToken, order.cashflow.toUint256(), to);
    }

    function cancelAndWithdrawNative(OrderId orderId, address to) public override returns (uint256) {
        Order memory order = orderManager.orders(orderId);
        cancel(orderId);
        Instrument memory instrument = contango.instrument(order.positionId.getSymbol());

        IERC20 cashflowToken = order.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
        if (nativeToken != cashflowToken) revert NotNativeToken(cashflowToken);

        return withdrawNative(order.cashflow.toUint256(), to);
    }

    function _deposit(IERC20 token, uint256 amount) internal returns (uint256) {
        if (msg.value > 0) {
            if (token == nativeToken) return depositNative();
            else revert NotNativeToken(token);
        } else {
            return deposit(token, amount);
        }
    }

    function _validatePermitAmount(int256 cashflow, EIP2098Permit memory permit) private pure {
        if (cashflow > 0 && int256(permit.amount) < cashflow) revert InsufficientPermitAmount(uint256(cashflow), permit.amount);
    }

    function _authorizeUpgrade(address) internal virtual override {
        if (msg.sender != Timelock.unwrap(timelock)) revert Unauthorised(msg.sender);
    }

    function _cashflowToken(TradeParams memory tradeParams) internal view returns (IERC20 cashflowToken) {
        Instrument memory instrument = contango.instrument(tradeParams.positionId.getSymbol());
        cashflowToken = tradeParams.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) revert SenderIsNotNativeToken(msg.sender, address(nativeToken));
    }

}

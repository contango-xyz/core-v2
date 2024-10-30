//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../libraries/DataTypes.sol";
import "../interfaces/IOrderManager.sol";
import "../utils/SimpleSpotExecutor.sol";
import { IPermit2 } from "../dependencies/Uniswap.sol";

struct LinkedOrderParams {
    uint128 limitPrice; // in quote currency
    uint128 tolerance; // 0.003e4 = 0.3%
    Currency cashflowCcy;
    uint32 deadline;
    OrderType orderType;
}

struct SwapData {
    address router;
    address spender;
    uint256 amountIn;
    uint256 minAmountOut;
    bytes swapBytes;
}

interface IMaestro is IContangoErrors, IOrderManagerErrors, IVaultErrors {

    error InvalidCashflow();
    error InsufficientPermitAmount(uint256 required, uint256 actual);
    error MismatchingPositionId(OrderId orderId1, OrderId orderId2);
    error NotNativeToken(IERC20 token);

    function contango() external view returns (IContango);
    function orderManager() external view returns (IOrderManager);
    function vault() external view returns (IVault);
    function positionNFT() external view returns (PositionNFT);
    function nativeToken() external view returns (IWETH9);
    function spotExecutor() external view returns (SimpleSpotExecutor);
    function permit2() external view returns (IPermit2);

    // =================== Funding primitives ===================

    function deposit(IERC20 token, uint256 amount) external payable returns (uint256);

    function depositNative() external payable returns (uint256);

    function depositWithPermit(IERC20 token, EIP2098Permit calldata permit, uint256 amount) external payable returns (uint256);

    function depositWithPermit2(IERC20 token, EIP2098Permit calldata permit, uint256 amount) external payable returns (uint256);

    function withdraw(IERC20 token, uint256 amount, address to) external payable returns (uint256);

    function withdrawNative(uint256 amount, address to) external payable returns (uint256);

    // =================== Trading actions ===================

    function trade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId, Trade memory);

    function depositAndTrade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId, Trade memory);

    function depositAndTradeWithPermit(TradeParams calldata tradeParams, ExecutionParams calldata execParams, EIP2098Permit calldata permit)
        external
        payable
        returns (PositionId, Trade memory);

    function tradeAndWithdraw(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
        external
        payable
        returns (PositionId positionId, Trade memory trade_, uint256 amount);

    function tradeAndWithdrawNative(TradeParams calldata tradeParams, ExecutionParams calldata execParams, address to)
        external
        payable
        returns (PositionId positionId, Trade memory trade_, uint256 amount);

    function swapAndDeposit(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData) external payable returns (uint256);

    function swapAndDepositNative(IERC20 tokenToDeposit, SwapData calldata swapData) external payable returns (uint256);

    function swapAndDepositWithPermit(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData, EIP2098Permit calldata permit)
        external
        payable
        returns (uint256);

    function swapAndDepositWithPermit2(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData, EIP2098Permit calldata permit)
        external
        payable
        returns (uint256);

    function tradeAndLinkedOrder(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId);

    function tradeAndLinkedOrders(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2);

    function depositTradeAndLinkedOrder(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId);

    function depositTradeAndLinkedOrderWithPermit(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams,
        EIP2098Permit calldata permit
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId);

    function depositTradeAndLinkedOrders(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2);

    function depositTradeAndLinkedOrdersWithPermit(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2,
        EIP2098Permit calldata permit
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2);

    function place(OrderParams memory params) external payable returns (OrderId orderId);

    function placeLinkedOrder(PositionId positionId, LinkedOrderParams memory params) external payable returns (OrderId orderId);

    function placeLinkedOrders(
        PositionId positionId,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) external payable returns (OrderId linkedOrderId1, OrderId linkedOrderId2);

    function depositAndPlace(OrderParams memory params) external payable returns (OrderId orderId);

    function depositAndPlaceWithPermit(OrderParams memory params, EIP2098Permit calldata permit)
        external
        payable
        returns (OrderId orderId);

    function cancel(OrderId orderId) external payable;

    function cancel(OrderId orderId1, OrderId orderId2) external payable;

    function cancelReplaceLinkedOrder(OrderId cancelOrderId, LinkedOrderParams memory newLinkedOrderParams)
        external
        payable
        returns (OrderId newLinkedOrderId);

    function cancelReplaceLinkedOrders(
        OrderId cancelOrderId1,
        OrderId cancelOrderId2,
        LinkedOrderParams memory newLinkedOrderParams1,
        LinkedOrderParams memory newLinkedOrderParams2
    ) external payable returns (OrderId newLinkedOrderId1, OrderId newLinkedOrderId2);

    function cancelAndWithdraw(OrderId orderId, address to) external payable returns (uint256);

    function cancelAndWithdrawNative(OrderId orderId, address to) external payable returns (uint256);

}

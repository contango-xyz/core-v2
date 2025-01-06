//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";

import { IPermit2 } from "../dependencies/Uniswap.sol";

import "../dependencies/PayableMulticall.sol";
import "../interfaces/IMaestro.sol";
import "../interfaces/IContango.sol";
import "../interfaces/IOrderManager.sol";
import "../interfaces/IVault.sol";
import "../libraries/Errors.sol";
import "../libraries/Validations.sol";
import "../libraries/ERC20Lib.sol";
import "../utils/SimpleSpotExecutor.sol";
import "../utils/Router.sol";

contract Maestro is IMaestro, UUPSUpgradeable, PayableMulticall {

    using SignedMath for int256;
    using SafeCast for *;
    using SafeERC20 for IERC20Permit;
    using ERC20Lib for *;
    using { validateCreatePositionPermissions, validateModifyPositionPermissions } for PositionNFT;

    uint256 public constant ALL = 0; // used to indicate that the full amount should be used, 0 is cheaper on calldata than type(uint256).max
    bytes32 public constant INTEGRATIONS_SLOT = keccak256("Maestro.integrations");

    Timelock public immutable timelock;
    IContango public immutable contango;
    IOrderManager public immutable orderManager;
    IVault public immutable vault;
    PositionNFT public immutable positionNFT;
    IWETH9 public immutable nativeToken;
    IPermit2 public immutable permit2;
    SimpleSpotExecutor public immutable spotExecutor;
    address public immutable treasury;
    Router public immutable router;

    constructor(
        Timelock _timelock,
        IContango _contango,
        IOrderManager _orderManager,
        IVault _vault,
        IPermit2 _permit2,
        SimpleSpotExecutor _spotExecutor,
        address _treasury,
        Router _router
    ) {
        timelock = _timelock;
        contango = _contango;
        orderManager = _orderManager;
        vault = _vault;
        permit2 = _permit2;
        spotExecutor = _spotExecutor;
        treasury = _treasury;
        positionNFT = _contango.positionNFT();
        nativeToken = _vault.nativeToken();
        router = _router;
    }

    function deposit(IERC20 token, uint256 amount) public payable override returns (uint256) {
        return vault.deposit(token, msg.sender, amount);
    }

    function depositNative() public payable returns (uint256) {
        return vault.depositNative{ value: msg.value }(msg.sender);
    }

    function applyPermit(IERC20 token, EIP2098Permit calldata permit, address spender) public {
        token.applyPermit(permit, msg.sender, spender);
    }

    function depositWithPermit(IERC20 token, EIP2098Permit calldata permit, uint256 amount) public payable override returns (uint256) {
        applyPermit(token, permit, address(vault));
        return deposit(token, amount == ALL ? permit.amount : amount);
    }

    function usePermit2(IERC20 token, EIP2098Permit calldata permit, uint256 amount, address to) public {
        permit2.pullFundsWithPermit2(token, permit, amount, msg.sender, to);
    }

    function depositWithPermit2(IERC20 token, EIP2098Permit calldata permit, uint256 amount) public payable override returns (uint256) {
        amount = amount == ALL ? permit.amount : amount;
        usePermit2(token, permit, amount, address(vault));
        return deposit(token, amount);
    }

    function _swapAndDeposit(address payer, IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData)
        internal
        returns (uint256)
    {
        if (payer != address(0)) tokenToSell.transferOut(payer, address(spotExecutor), swapData.amountIn);
        uint256 output = spotExecutor.executeSwap({
            tokenToSell: tokenToSell,
            tokenToBuy: tokenToDeposit,
            spender: swapData.spender,
            amountIn: swapData.amountIn,
            minAmountOut: swapData.minAmountOut,
            router: swapData.router,
            swapBytes: swapData.swapBytes,
            to: address(vault)
        });
        return deposit(tokenToDeposit, output);
    }

    function swapAndDeposit(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData)
        public
        payable
        override
        returns (uint256)
    {
        return _swapAndDeposit(msg.sender, tokenToSell, tokenToDeposit, swapData);
    }

    function swapAndDepositNative(IERC20 tokenToDeposit, SwapData calldata swapData) public payable override returns (uint256) {
        nativeToken.deposit{ value: msg.value }();
        return _swapAndDeposit(address(this), nativeToken, tokenToDeposit, swapData);
    }

    function swapAndDepositWithPermit(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData, EIP2098Permit calldata permit)
        public
        payable
        override
        returns (uint256)
    {
        applyPermit(tokenToSell, permit, address(this));
        return _swapAndDeposit(msg.sender, tokenToSell, tokenToDeposit, swapData);
    }

    function swapAndDepositWithPermit2(IERC20 tokenToSell, IERC20 tokenToDeposit, SwapData calldata swapData, EIP2098Permit calldata permit)
        public
        payable
        override
        returns (uint256)
    {
        usePermit2(tokenToSell, permit, swapData.amountIn, address(spotExecutor));
        return _swapAndDeposit(address(0), tokenToSell, tokenToDeposit, swapData);
    }

    function withdraw(IERC20 token, uint256 amount, address to) public payable override returns (uint256) {
        if (amount == ALL) amount = vault.balanceOf(token, msg.sender);
        if (amount == 0) return 0;
        return vault.withdraw(token, msg.sender, amount, to);
    }

    function withdrawNative(uint256 amount, address to) public payable override returns (uint256) {
        if (amount == ALL) amount = vault.balanceOf(nativeToken, msg.sender);
        if (amount == 0) return 0;
        return vault.withdrawNative(msg.sender, amount, to);
    }

    function swapAndWithdraw(IERC20 tokenToSell, IERC20 tokenToReceive, SwapData calldata swapData, address to)
        public
        payable
        returns (uint256)
    {
        withdraw(tokenToSell, swapData.amountIn, address(spotExecutor));
        return spotExecutor.executeSwap({
            tokenToSell: tokenToSell,
            tokenToBuy: tokenToReceive,
            spender: swapData.spender,
            amountIn: swapData.amountIn,
            minAmountOut: swapData.minAmountOut,
            router: swapData.router,
            swapBytes: swapData.swapBytes,
            to: to
        });
    }

    function swapAndWithdrawNative(IERC20 tokenToSell, SwapData calldata swapData, address payable to)
        public
        payable
        returns (uint256 output)
    {
        withdraw(tokenToSell, swapData.amountIn, address(spotExecutor));
        output = spotExecutor.executeSwap({
            tokenToSell: tokenToSell,
            tokenToBuy: nativeToken,
            spender: swapData.spender,
            amountIn: swapData.amountIn,
            minAmountOut: swapData.minAmountOut,
            router: swapData.router,
            swapBytes: swapData.swapBytes,
            to: address(this)
        });
        nativeToken.transferOutNative(to, output);
    }

    function tradeWithFees(TradeParams memory tradeParams, ExecutionParams calldata execParams, FeeParams memory feeParams)
        public
        payable
        returns (PositionId positionId_, Trade memory trade_)
    {
        if (positionNFT.exists(tradeParams.positionId)) positionNFT.validateModifyPositionPermissions(tradeParams.positionId);
        if (feeParams.amount > 0 && tradeParams.cashflow > 0) withdraw(feeParams.token, feeParams.amount, treasury);
        if (tradeParams.cashflow == type(int256).max) {
            tradeParams.cashflow = vault.balanceOf(_cashflowToken(tradeParams), msg.sender).toInt256();
        }
        (positionId_, trade_) = contango.tradeOnBehalfOf(tradeParams, execParams, msg.sender);
        if (feeParams.amount > 0) {
            if (tradeParams.cashflow <= 0) withdraw(feeParams.token, feeParams.amount, treasury);
            emit FeeCollected(positionId_, msg.sender, treasury, feeParams.token, feeParams.amount, feeParams.basisPoints);
        }
    }

    function trade(TradeParams calldata tradeParams, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId, Trade memory)
    {
        FeeParams memory feeParams;
        return tradeWithFees(tradeParams, execParams, feeParams);
    }

    function tradeAndLinkedOrder(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
        FeeParams memory feeParams;
        return tradeAndLinkedOrderWithFees(tradeParams, execParams, linkedOrderParams, feeParams);
    }

    function tradeAndLinkedOrderWithFees(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams,
        FeeParams memory feeParams
    ) public payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId) {
        (positionId, trade_) = tradeWithFees(tradeParams, execParams, feeParams);
        linkedOrderId = placeLinkedOrder(positionId, linkedOrderParams);
    }

    function tradeAndLinkedOrders(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2
    ) external payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2) {
        FeeParams memory feeParams;
        return tradeAndLinkedOrdersWithFees(tradeParams, execParams, linkedOrderParams1, linkedOrderParams2, feeParams);
    }

    function tradeAndLinkedOrdersWithFees(
        TradeParams calldata tradeParams,
        ExecutionParams calldata execParams,
        LinkedOrderParams memory linkedOrderParams1,
        LinkedOrderParams memory linkedOrderParams2,
        FeeParams memory feeParams
    ) public payable returns (PositionId positionId, Trade memory trade_, OrderId linkedOrderId1, OrderId linkedOrderId2) {
        (positionId, trade_) = tradeWithFees(tradeParams, execParams, feeParams);
        linkedOrderId1 = placeLinkedOrder(positionId, linkedOrderParams1);
        linkedOrderId2 = placeLinkedOrder(positionId, linkedOrderParams2);
    }

    function placeLinkedOrder(PositionId positionId, LinkedOrderParams memory params) public payable override returns (OrderId orderId) {
        positionNFT.validateModifyPositionPermissions(positionId);
        orderId = _placeLinkedOrder(positionId, params);
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

    function cancel(OrderId orderId) public payable override {
        if (!positionNFT.isApprovedForAll(orderManager.orders(orderId).owner, msg.sender)) revert Unauthorised(msg.sender);
        orderManager.cancel(orderId);
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

    function _authorizeUpgrade(address) internal virtual override onlyTimelock { }

    function _cashflowToken(TradeParams memory tradeParams) internal view returns (IERC20 cashflowToken) {
        Instrument memory instrument = contango.instrument(tradeParams.positionId.getSymbol());
        cashflowToken = tradeParams.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) revert SenderIsNotNativeToken(msg.sender, address(nativeToken));
    }

    // =================== Routing ===================

    /// @dev Allow users to route calls to a contract without inheriting this contract's permissions, to be used with batch
    function route(address integration, uint256 value, bytes calldata data) external payable returns (bytes memory result) {
        require(isIntegration(integration), UnknownIntegration(integration));
        return router.route{ value: value }(integration, value, data);
    }

    function isIntegration(address integration) public view returns (bool) {
        return _integrationSlot(integration).value;
    }

    function setIntegration(address integration, bool whitelisted) public onlyTimelock {
        _integrationSlot(integration).value = whitelisted;
        emit IntegrationSet(integration, whitelisted);
    }

    function _integrationSlot(address integration) private pure returns (StorageSlot.BooleanSlot storage slot) {
        return StorageSlot.getBooleanSlot(keccak256(abi.encodePacked(integration, INTEGRATIONS_SLOT)));
    }

    function transferPosition(PositionId positionId, address to, bytes memory data) external payable override {
        positionNFT.safeTransferFrom(msg.sender, to, positionId.asUint(), data);
    }

    modifier onlyTimelock() {
        if (msg.sender != Timelock.unwrap(timelock)) revert Unauthorised(msg.sender);
        _;
    }

}

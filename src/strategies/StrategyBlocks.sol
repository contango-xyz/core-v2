//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import { IPermit2 } from "../dependencies/Uniswap.sol";
import "@contango/erc721Permit2/interfaces/IERC721Permit2.sol";
import "../moneymarkets/ContangoLens.sol";
import "../interfaces/IMaestro.sol";
import "../libraries/ERC20Lib.sol";
import "./PositionPermit.sol";

interface IStrategyBlocksEvents {

    event BeginStrategy(PositionId indexed positionId, address indexed owner);
    event EndStrategy(PositionId indexed positionId, address indexed owner);
    event SwapExecuted(address indexed trader, IERC20 tokenIn, uint256 amountIn, IERC20 tokenOut, uint256 amountOut);

}

abstract contract StrategyBlocks is IERC721Receiver, IStrategyBlocksEvents, AccessControl {

    using ERC20Lib for *;
    using SafeERC20 for IERC20Permit;
    using Address for address payable;

    error PositionLeftBehind();
    error InvalidCallback();
    error NotNativeToken();
    error NotPositionNFT();

    struct SwapResult {
        address trader;
        IERC20 tokenIn;
        uint256 amountIn;
        IERC20 tokenOut;
        uint256 amountOut;
    }

    uint256 public constant ALL = type(uint256).max;
    uint256 public constant BALANCE = type(uint256).max - 1;

    IContango public immutable contango;
    IVault public immutable vault;
    PositionNFT public immutable positionNFT;
    IERC721Permit2 public immutable erc721Permit2;
    ContangoLens public immutable lens;
    SimpleSpotExecutor public immutable spotExecutor;
    IPermit2 public immutable erc20Permit2;
    IWETH9 public immutable nativeToken;

    bytes32 internal flashLoanHash;

    constructor(Timelock timelock, IMaestro _maestro, IERC721Permit2 _erc721Permit2, ContangoLens _lens) {
        // Grant the admin role to the timelock by default
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));

        contango = _maestro.contango();
        vault = _maestro.vault();
        positionNFT = contango.positionNFT();
        spotExecutor = _maestro.spotExecutor();
        erc721Permit2 = _erc721Permit2;
        lens = _lens;
        erc20Permit2 = _maestro.permit2();
        nativeToken = _maestro.nativeToken();
    }

    // ======================== Public functions ========================

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        if (msg.sender != address(positionNFT)) revert NotPositionNFT();

        // When's not a position creation
        if (operator != address(contango)) {
            emit BeginStrategy(fromUint(tokenId), from);
            _onPositionReceived(operator, from, tokenId, data);
            emit EndStrategy(fromUint(tokenId), from);
        }

        return this.onERC721Received.selector;
    }

    // ======================== Modifiers ========================

    modifier validFlashloan(bytes memory data) {
        if (keccak256(data) != flashLoanHash) revert InvalidCallback();
        _;
        delete flashLoanHash;
    }

    // ======================== Internal functions ========================

    function _onPositionReceived(address operator, address from, uint256 tokenId, bytes calldata data) internal virtual;

    function _vaultDeposit(IERC20 asset, uint256 amount) internal returns (uint256 actual) {
        if (amount == ALL) amount = asset.balanceOf(address(vault)) - vault.totalBalanceOf(asset);
        return vault.depositTo(asset, address(this), amount);
    }

    function _vaultDepositNative() internal returns (uint256 actual) {
        return vault.depositNative{ value: msg.value }(address(this));
    }

    function _vaultWithdraw(IERC20 asset, uint256 amount, address to) internal returns (uint256 actual) {
        if (amount == BALANCE) amount = vault.balanceOf(asset, address(this));
        return vault.withdraw(asset, address(this), amount, to);
    }

    function _vaultWithdrawNative(uint256 amount, address payable to) internal returns (uint256 actual) {
        if (amount == BALANCE) amount = vault.balanceOf(nativeToken, address(this));
        return vault.withdrawNative(address(this), amount, to);
    }

    function _positionDeposit(PositionId positionId, uint256 amount) internal returns (PositionId positionId_, Trade memory trade_) {
        if (amount == BALANCE) amount = vault.balanceOf(contango.instrument(positionId.getSymbol()).base, address(this));
        return _trade(_depositParams(positionId, amount));
    }

    function _positionBorrow(PositionId positionId, uint256 amount) internal returns (PositionId positionId_, Trade memory trade_) {
        return _trade(_borrowParams(positionId, amount));
    }

    function _positionWithdraw(PositionId positionId, uint256 amount) internal returns (PositionId positionId_, Trade memory trade_) {
        return _trade(_withdrawParams(positionId, amount));
    }

    function _positionRepay(PositionId positionId, uint256 amount) internal returns (PositionId positionId_, Trade memory trade_) {
        if (amount == ALL) amount = lens.balances(positionId).debt;
        if (amount == BALANCE) amount = vault.balanceOf(contango.instrument(positionId.getSymbol()).quote, address(this));
        return _trade(_repayParams(positionId, amount));
    }

    function _positionClose(PositionId positionId, address owner) internal returns (PositionId positionId_, Trade memory trade_) {
        (positionId_, trade_) = _trade(_closeParams(positionId));
        contango.donatePosition(positionId, owner);
    }

    function _trade(TradeParams memory params, ExecutionParams memory execution)
        internal
        returns (PositionId positionId_, Trade memory trade_)
    {
        return contango.trade(params, execution);
    }

    function _swapFromVault(address user, SwapData memory swapData, IERC20 tokenToSell, IERC20 tokenToBuy)
        internal
        returns (SwapResult memory result)
    {
        vault.withdraw(tokenToSell, address(this), swapData.amountIn, address(spotExecutor));
        result = _swap(user, swapData, tokenToSell, tokenToBuy, address(vault));
        vault.depositTo(tokenToBuy, address(this), result.amountOut);
    }

    function _swap(address user, SwapData memory swapData, IERC20 tokenToSell, IERC20 tokenToBuy, address to)
        internal
        returns (SwapResult memory)
    {
        uint256 amountOut = spotExecutor.executeSwap({
            tokenToSell: tokenToSell,
            tokenToBuy: tokenToBuy,
            amountIn: swapData.amountIn,
            minAmountOut: swapData.minAmountOut,
            spender: swapData.spender,
            router: swapData.router,
            swapBytes: swapData.swapBytes,
            to: to
        });

        emit SwapExecuted(user, tokenToSell, swapData.amountIn, tokenToBuy, amountOut);
        return SwapResult(user, tokenToSell, swapData.amountIn, tokenToBuy, amountOut);
    }

    function _wrapNativeToken(address to) internal returns (uint256) {
        uint256 amount = msg.value;
        nativeToken.deposit{ value: amount }();
        return nativeToken.transferOut(address(this), to, amount);
    }

    function _unwrapNativeToken(uint256 amount, address payable to) internal returns (uint256) {
        if (amount == BALANCE) amount = nativeToken.balanceOf(address(this));
        return nativeToken.transferOutNative(to, amount);
    }

    function _returnPositions(PositionId long, PositionId short, address owner) internal {
        _returnPosition(long, owner);
        _returnPosition(short, owner);
    }

    function _returnPosition(PositionId positionId, address owner) internal {
        if (positionNFT.exists(positionId)) {
            positionNFT.safeTransferFrom(address(this), owner, positionId.asUint());
            emit EndStrategy(positionId, owner);
        }
    }

    function _trade(TradeParams memory params) internal returns (PositionId positionId_, Trade memory trade_) {
        ExecutionParams memory noExecution;
        return _trade(params, noExecution);
    }

    function _borrowParams(PositionId positionId, uint256 amount) internal pure returns (TradeParams memory) {
        return TradeParams({ positionId: positionId, quantity: 0, limitPrice: 0, cashflowCcy: Currency.Quote, cashflow: -int256(amount) });
    }

    function _repayParams(PositionId positionId, uint256 amount) internal pure returns (TradeParams memory) {
        return TradeParams({ positionId: positionId, quantity: 0, limitPrice: 0, cashflowCcy: Currency.Quote, cashflow: int256(amount) });
    }

    function _withdrawParams(PositionId positionId, uint256 amount) internal pure returns (TradeParams memory) {
        int256 iAmount = -int256(amount);
        return TradeParams({ positionId: positionId, quantity: iAmount, limitPrice: 0, cashflowCcy: Currency.Base, cashflow: iAmount });
    }

    function _depositParams(PositionId positionId, uint256 amount) internal pure returns (TradeParams memory) {
        int256 iAmount = int256(amount);
        return TradeParams({ positionId: positionId, quantity: iAmount, limitPrice: 0, cashflowCcy: Currency.Base, cashflow: iAmount });
    }

    function _closeParams(PositionId positionId) internal pure returns (TradeParams memory) {
        return TradeParams({ positionId: positionId, quantity: type(int128).min, limitPrice: 0, cashflowCcy: Currency.Base, cashflow: -1 });
    }

    function _pullPosition(PositionPermit memory permit, address owner) internal returns (PositionId positionId) {
        positionId = permit.positionId;
        uint256 tokenId = positionId.asUint();
        erc721Permit2.permitTransferFrom({
            permit: IERC721Permit2.PermitTransferFrom({
                permitted: IERC721Permit2.TokenPermissions({ token: address(positionNFT), tokenId: tokenId }),
                nonce: uint256(keccak256(abi.encode(owner, positionNFT, positionId, permit.deadline))),
                deadline: permit.deadline
            }),
            transferDetails: IERC721Permit2.SignatureTransferDetails({ to: address(this), tokenId: tokenId }),
            owner: owner,
            signature: abi.encodePacked(permit.r, permit.vs)
        });
    }

    function _pullFundsWithPermit(address token, EIP2098Permit memory permit, uint256 amount, address owner, address to)
        internal
        returns (uint256)
    {
        // Inspired by https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol
        IERC20Permit(token).safePermit({
            owner: owner,
            spender: address(this),
            value: permit.amount,
            deadline: permit.deadline,
            r: permit.r,
            v: uint8(uint256(permit.vs >> 255)) + 27,
            s: permit.vs & bytes32(uint256(type(int256).max))
        });
        return IERC20(token).transferOut(owner, to, amount);
    }

    function _pullFundsWithPermit2(IERC20 token, EIP2098Permit memory permit, uint256 amount, address owner, address to)
        public
        returns (uint256)
    {
        erc20Permit2.permitTransferFrom({
            permit: IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({ token: address(token), amount: permit.amount }),
                nonce: uint256(keccak256(abi.encode(owner, token, permit.amount, permit.deadline))),
                deadline: permit.deadline
            }),
            transferDetails: IPermit2.SignatureTransferDetails({ to: to, requestedAmount: amount }),
            owner: owner,
            signature: abi.encodePacked(permit.r, permit.vs)
        });
        return amount;
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) revert NotNativeToken();
    }

    function retrieve(IERC20 token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        token.transferBalance(to);
    }

    function retrieveNative(address payable to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        to.sendValue(address(this).balance);
    }

    function retrieve(PositionId positionId, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        positionNFT.safeTransferFrom(address(this), to, positionId.asUint());
    }

    function retrieveFromVault(IERC20 token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _vaultWithdraw(token, BALANCE, to);
    }

}

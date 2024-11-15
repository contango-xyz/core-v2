//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./StrategyBlocks.sol";

enum Step {
    TakeFlashloan,
    RepayFlashloan,
    VaultDeposit,
    VaultWithdraw,
    Swap,
    PositionDeposit,
    PositionWithdraw,
    PositionBorrow,
    PositionRepay,
    PositionClose,
    PullFundsWithPermit,
    PullFundsWithPermit2,
    PullPosition,
    Trade,
    VaultDepositNative,
    VaultWithdrawNative,
    SwapFromVault,
    WrapNativeToken,
    UnwrapNativeToken,
    EmitEvent
}

type PositionN is uint256;

PositionN constant POSITION_ONE = PositionN.wrap(1);
PositionN constant POSITION_TWO = PositionN.wrap(2);

function positionNEquals(PositionN a, PositionN b) pure returns (bool) {
    return PositionN.unwrap(a) == PositionN.unwrap(b);
}

function positionNNotEquals(PositionN a, PositionN b) pure returns (bool) {
    return !positionNEquals(a, b);
}

using { positionNEquals as ==, positionNNotEquals as != } for PositionN global;

struct StepCall {
    Step step;
    bytes data;
}

struct StepResult {
    Step step;
    bytes data;
}

library StackLib {

    struct Stack {
        PositionId position1;
        PositionId position2;
        address repayTo;
        IERC20[10] tokens;
        uint256 tokenCount;
    }

    function loadPositionId(Stack memory stack, PositionId positionId, PositionN n) internal pure returns (PositionId) {
        if (positionId.asUint() == 0) positionId = (n == POSITION_ONE ? stack.position1 : stack.position2);
        return positionId;
    }

    function storePositionId(
        Stack memory stack,
        PositionId positionId,
        PositionN n,
        function (Symbol) external view returns (Instrument memory) instrument
    ) internal view returns (Stack memory) {
        if (n == POSITION_ONE) {
            if (stack.position1 != positionId) {
                stack.position1 = positionId;
                storePositionTokens(stack, positionId, instrument);
            }
        } else {
            if (stack.position2 != positionId) {
                stack.position2 = positionId;
                storePositionTokens(stack, positionId, instrument);
            }
        }
        return stack;
    }

    function storePositionTokens(
        Stack memory stack,
        PositionId positionId,
        function (Symbol) external view returns (Instrument memory) instrument
    ) internal view {
        Instrument memory i = instrument(positionId.getSymbol());
        storeToken(stack, i.base);
        storeToken(stack, i.quote);
    }

    function storeToken(Stack memory stack, IERC20 token) internal pure {
        for (uint256 i = 0; i < stack.tokenCount; i++) {
            if (stack.tokens[i] == token) return;
        }
        stack.tokens[stack.tokenCount++] = token;
    }

}

contract StrategyBuilder is StrategyBlocks {

    using ERC20Lib for *;
    using SafeERC20 for IERC20Permit;
    using StackLib for StackLib.Stack;

    error InvalidStep(Step step);

    event StragegyExecuted(address indexed user, bytes32 indexed action, PositionId position1, PositionId position2, bytes data);

    constructor(IMaestro _maestro, IERC721Permit2 _erc721Permit2, ContangoLens _lens) StrategyBlocks(_maestro, _erc721Permit2, _lens) { }

    // ======================== Public functions ========================

    function process(StepCall[] memory steps) external payable returns (StepResult[] memory results) {
        results = process(steps, msg.sender);
    }

    function process(StepCall[] memory steps, address returnPositionsTo)
        public
        payable
        whenNotPaused
        returns (StepResult[] memory results)
    {
        StackLib.Stack memory stack;
        results = new StepResult[](steps.length);
        address user = msg.sender; // User MUST be msg.sender to enforce that permits can not be used by someone else's
        (, stack, results) = _actionProcessor(steps, 0, stack, user, results);
        _returnPositions(stack.position1, stack.position2, returnPositionsTo);
        _sweepDust(stack.tokens, stack.tokenCount, payable(returnPositionsTo));
    }

    function continueActionProcessing(address, address repayTo, address, uint256, uint256, bytes calldata data)
        external
        validFlashloan(data)
        returns (bytes memory result)
    {
        (StepCall[] memory steps, uint256 offset, StackLib.Stack memory stack, address user, StepResult[] memory results) =
            abi.decode(data, (StepCall[], uint256, StackLib.Stack, address, StepResult[]));
        stack.repayTo = repayTo;
        (offset, stack, results) = _actionProcessor(steps, offset, stack, user, results);
        return abi.encode(offset, stack, results);
    }

    // ======================== Internal functions ========================

    function _onPositionReceived(address, address from, uint256, bytes calldata data) internal override {
        StepCall[] memory steps = abi.decode(data, (StepCall[]));
        StepResult[] memory results = new StepResult[](steps.length);
        StackLib.Stack memory stack;
        address user = from; // User MUST be the position owner to enforce that permits can not be used by someone else's
        (, stack, results) = _actionProcessor(steps, 0, stack, user, results);
        _returnPositions(stack.position1, stack.position2, user);
        _sweepDust(stack.tokens, stack.tokenCount, payable(user));
    }

    function _actionProcessor(
        StepCall[] memory steps,
        uint256 offset,
        StackLib.Stack memory stack,
        address user,
        StepResult[] memory results
    ) internal returns (uint256 offset_, StackLib.Stack memory stack_, StepResult[] memory results_) {
        results_ = results;
        stack_ = stack;
        for (offset_ = offset; offset_ < steps.length; offset_++) {
            StepCall memory step = steps[offset_];
            results[offset_].step = step.step;

            if (step.step == Step.VaultDeposit) {
                (IERC20 asset, uint256 amount) = abi.decode(step.data, (IERC20, uint256));
                results[offset_].data = abi.encode(_vaultDeposit(asset, amount));
                stack_.storeToken(asset);
            } else if (step.step == Step.VaultDepositNative) {
                results[offset_].data = abi.encode(_vaultDepositNative());
                stack_.storeToken(nativeToken);
            } else if (step.step == Step.PullFundsWithPermit) {
                (address token, EIP2098Permit memory permit, uint256 amount, address to) =
                    abi.decode(step.data, (address, EIP2098Permit, uint256, address));
                results[offset_].data = abi.encode(_pullFundsWithPermit(token, permit, amount, user, to));
                stack_.storeToken(IERC20(token));
            } else if (step.step == Step.PullFundsWithPermit2) {
                (IERC20 token, EIP2098Permit memory permit, uint256 amount, address to) =
                    abi.decode(step.data, (IERC20, EIP2098Permit, uint256, address));
                results[offset_].data = abi.encode(_pullFundsWithPermit2(token, permit, amount, user, to));
                stack_.storeToken(token);
            } else if (step.step == Step.VaultWithdraw) {
                (IERC20 asset, uint256 amount, address to) = abi.decode(step.data, (IERC20, uint256, address));
                results[offset_].data = abi.encode(_vaultWithdraw(asset, amount, to));
                stack_.storeToken(asset);
            } else if (step.step == Step.VaultWithdrawNative) {
                (uint256 amount, address payable to) = abi.decode(step.data, (uint256, address));
                results[offset_].data = abi.encode(_vaultWithdrawNative(amount, to));
                stack_.storeToken(nativeToken);
            } else if (step.step == Step.WrapNativeToken) {
                results[offset_].data = abi.encode(_wrapNativeToken(abi.decode(step.data, (address))));
                stack_.storeToken(nativeToken);
            } else if (step.step == Step.UnwrapNativeToken) {
                (uint256 amount, address payable to) = abi.decode(step.data, (uint256, address));
                results[offset_].data = abi.encode(_unwrapNativeToken(amount, to));
                stack_.storeToken(nativeToken);
            } else if (step.step == Step.TakeFlashloan) {
                (IERC7399 flashLoanProvider, address asset, uint256 amount) = abi.decode(step.data, (IERC7399, address, uint256));
                (offset_, stack_, results_) = abi.decode(
                    _takeFlashloan(flashLoanProvider, asset, amount, steps, offset_ + 1, stack_, user, results_),
                    (uint256, StackLib.Stack, StepResult[])
                );
                stack_.storeToken(IERC20(asset));
            } else if (step.step == Step.RepayFlashloan) {
                (IERC20 asset, uint256 amount) = abi.decode(step.data, (IERC20, uint256));
                results[offset_].data = abi.encode(_vaultWithdraw(asset, amount, stack_.repayTo));
                stack_.storeToken(asset);
            } else if (step.step == Step.PositionDeposit) {
                (PositionId positionId, PositionN n, uint256 amount) = abi.decode(step.data, (PositionId, PositionN, uint256));
                Trade memory trade;
                (positionId, trade) = _positionDeposit(stack_.loadPositionId(positionId, n), amount);
                stack_.storePositionId(positionId, n, contango.instrument);
                results[offset_].data = abi.encode(positionId, trade);
            } else if (step.step == Step.PositionBorrow) {
                (PositionId positionId, PositionN n, uint256 amount) = abi.decode(step.data, (PositionId, PositionN, uint256));
                Trade memory trade;
                (positionId, trade) = _positionBorrow(stack_.loadPositionId(positionId, n), amount);
                stack_.storePositionId(positionId, n, contango.instrument);
                results[offset_].data = abi.encode(positionId, trade);
            } else if (step.step == Step.PositionWithdraw) {
                (PositionId positionId, PositionN n, uint256 amount) = abi.decode(step.data, (PositionId, PositionN, uint256));
                Trade memory trade;
                (positionId, trade) = _positionWithdraw(stack_.loadPositionId(positionId, n), amount);
                stack_.storePositionId(positionId, n, contango.instrument);
                results[offset_].data = abi.encode(positionId, trade);
            } else if (step.step == Step.PositionRepay) {
                (PositionId positionId, PositionN n, uint256 amount) = abi.decode(step.data, (PositionId, PositionN, uint256));
                Trade memory trade;
                (positionId, trade) = _positionRepay(stack_.loadPositionId(positionId, n), amount);
                stack_.storePositionId(positionId, n, contango.instrument);
                results[offset_].data = abi.encode(positionId, trade);
            } else if (step.step == Step.PositionClose) {
                (PositionId positionId, PositionN n) = abi.decode(step.data, (PositionId, PositionN));
                Trade memory trade;
                (positionId, trade) = _positionClose(stack_.loadPositionId(positionId, n), user);
                stack_.storePositionId(positionId, n, contango.instrument);
                results[offset_].data = abi.encode(positionId, trade);
            } else if (step.step == Step.Swap) {
                (SwapData memory swapData, IERC20 tokenToSell, IERC20 tokenToBuy, address to) =
                    abi.decode(step.data, (SwapData, IERC20, IERC20, address));
                results[offset_].data = abi.encode(_swap(user, swapData, tokenToSell, tokenToBuy, to));
                stack_.storeToken(tokenToSell);
                stack_.storeToken(tokenToBuy);
            } else if (step.step == Step.SwapFromVault) {
                (SwapData memory swapData, IERC20 tokenToSell, IERC20 tokenToBuy) = abi.decode(step.data, (SwapData, IERC20, IERC20));
                results[offset_].data = abi.encode(_swapFromVault(user, swapData, tokenToSell, tokenToBuy));
                stack_.storeToken(tokenToSell);
                stack_.storeToken(tokenToBuy);
            } else if (step.step == Step.Trade) {
                (PositionN n, TradeParams memory tp, ExecutionParams memory ep) =
                    abi.decode(step.data, (PositionN, TradeParams, ExecutionParams));
                (PositionId positionId, Trade memory trade) = _trade(tp, ep);
                results[offset_].data = abi.encode(positionId, trade);
                stack_.storePositionId(positionId, n, contango.instrument);
            } else if (step.step == Step.PullPosition) {
                PositionId positionId = _pullPosition(abi.decode(step.data, (PositionPermit)), user);
                stack_.storePositionTokens(positionId, contango.instrument);
                results[offset_].data = abi.encode(positionId);
            } else if (step.step == Step.EmitEvent) {
                (bytes32 action, bytes memory data) = abi.decode(step.data, (bytes32, bytes));
                emit StragegyExecuted(user, action, stack_.position1, stack_.position2, data);
            } else {
                revert InvalidStep(step.step);
            }
        }
    }

    function _takeFlashloan(
        IERC7399 flashLoanProvider,
        address asset,
        uint256 amount,
        StepCall[] memory steps,
        uint256 offset,
        StackLib.Stack memory stack,
        address user,
        StepResult[] memory results
    ) internal returns (bytes memory) {
        bytes memory data = abi.encode(steps, offset, stack, user, results);
        _flashLoanHash(keccak256(data));
        return flashLoanProvider.flash(address(vault), asset, amount, data, this.continueActionProcessing);
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../dependencies/IWETH9.sol";
import "../libraries/ERC20Lib.sol";

contract DineroSwap {

    using ERC20Lib for IERC20;
    using ERC20Lib for IWETH9;
    using ERC20Lib for IERC4626;
    using SafeERC20 for IERC20;

    uint256 internal constant DENOMINATOR = 1_000_000;

    error InvalidEthSender(address sender);

    IWETH9 public immutable weth;
    IERC20 public immutable pxEth;
    IERC4626 public immutable autoPxEth;
    IPirexEth public immutable pirexEth;

    constructor(IWETH9 _weth, IPirexEth _pirexEth) {
        weth = _weth;
        pirexEth = _pirexEth;
        pxEth = _pirexEth.pxEth();
        autoPxEth = _pirexEth.autoPxEth();
    }

    function quoteBuy(uint256 amount) external view returns (uint256 pxAmount, uint256 apxAmount, uint256 feeAmount) {
        (pxAmount, feeAmount) = _computeAssetAmounts(IPirexEth.Fees.Deposit, amount);
        apxAmount = autoPxEth.previewDeposit(pxAmount);
    }

    function buy(uint256 amount) external {
        weth.transferOut(msg.sender, address(this), amount);
        weth.withdraw(amount);
        pirexEth.deposit{ value: amount }(msg.sender, true);
    }

    function quoteSell(uint256 amount) external view returns (uint256 pxAmount, uint256 ethAmount, uint256 feeAmount) {
        pxAmount = autoPxEth.previewRedeem(amount);
        (ethAmount, feeAmount) = _computeAssetAmounts(IPirexEth.Fees.InstantRedemption, pxAmount);
    }

    function sell(uint256 amount) external {
        autoPxEth.transferOut(msg.sender, address(this), amount);
        uint256 pxAmount = autoPxEth.redeem(amount, address(this), address(this));
        pxEth.forceApprove(address(pirexEth), pxAmount);
        (uint256 postFeeAmount,) = pirexEth.instantRedeemWithPxEth(pxAmount, address(this));
        weth.deposit{ value: postFeeAmount }();
        weth.transferOut(address(this), msg.sender, postFeeAmount);
    }

    function _computeAssetAmounts(IPirexEth.Fees f, uint256 assets) internal view returns (uint256 postFeeAmount, uint256 feeAmount) {
        feeAmount = (assets * pirexEth.fees(f)) / DENOMINATOR;
        postFeeAmount = assets - feeAmount;
    }

    receive() external payable {
        if (msg.sender != address(weth) && msg.sender != address(pirexEth)) revert InvalidEthSender(msg.sender);
    }

}

interface IPirexEth {

    // Configurable fees
    enum Fees {
        Deposit,
        Redemption,
        InstantRedemption
    }

    error AccountNotApproved();
    error DepositingEtherNotPaused();
    error DepositingEtherPaused();
    error EmptyArray();
    error ExceedsMax();
    error InvalidAmount();
    error InvalidFee();
    error InvalidMaxFee();
    error InvalidMaxProcessedCount();
    error InvalidToken();
    error MismatchedArrayLengths();
    error NoETH();
    error NoETHAllowed();
    error NoPartialInitiateRedemption();
    error NoUsedValidator();
    error NoValidatorExit();
    error NotEnoughBuffer();
    error NotEnoughETH();
    error NotEnoughValidators();
    error NotPaused();
    error NotRewardRecipient();
    error NotWithdrawable();
    error Paused();
    error StatusNotDissolvedOrSlashed();
    error StatusNotWithdrawableOrStaking();
    error UnrecorgnisedContract();
    error ValidatorNotStaking();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroMultiplier();

    function fees(Fees f) external view returns (uint32);
    function deposit(address receiver, bool shouldCompound) external payable returns (uint256 postFeeAmount, uint256 feeAmount);
    function instantRedeemWithPxEth(uint256 _assets, address _receiver) external returns (uint256 postFeeAmount, uint256 feeAmount);
    function pxEth() external view returns (IERC20);
    function autoPxEth() external view returns (IERC4626);

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../libraries/ERC20Lib.sol";

import "./dependencies/IComet.sol";
import "./dependencies/ICometRewards.sol";

import "../BaseMoneyMarket.sol";
import "./CometReverseLookup.sol";

contract CometMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for IERC20;
    using SafeERC20 for IERC20;

    bool public constant override NEEDS_ACCOUNT = true;

    CometReverseLookup public immutable reverseLookup;
    ICometRewards public immutable rewards;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, CometReverseLookup _reverseLookup, ICometRewards _rewards)
        BaseMoneyMarket(_moneyMarketId, _contango)
    {
        reverseLookup = _reverseLookup;
        rewards = _rewards;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();
        IComet comet = reverseLookup.comet(positionId.getPayload());
        collateralAsset.forceApprove(address(comet), type(uint256).max);
        debtAsset.forceApprove(address(comet), type(uint256).max);
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        reverseLookup.comet(positionId.getPayload()).supply(asset, actualAmount = asset.transferOut(payer, address(this), amount));
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        actualAmount = Math.min(amount, comet.userCollateral(address(this), asset).balance);
        comet.withdrawTo(to, asset, actualAmount);
    }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        reverseLookup.comet(positionId.getPayload()).withdrawTo(to, asset, actualAmount = amount);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        comet.supply(asset, actualAmount = asset.transferOut(payer, address(this), Math.min(amount, comet.borrowBalanceOf(address(this)))));
    }

    function _claimRewards(PositionId positionId, IERC20, IERC20, address to) internal virtual override {
        rewards.claimTo({ comet: reverseLookup.comet(positionId.getPayload()), from: address(this), to: to, shouldAccrue: true });
    }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal view override returns (uint256 balance) {
        balance = reverseLookup.comet(positionId.getPayload()).userCollateral(address(this), asset).balance;
    }

}

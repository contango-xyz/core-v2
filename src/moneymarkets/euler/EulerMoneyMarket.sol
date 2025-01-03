//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { MM_EULER } from "script/constants.sol";

import "../../libraries/ERC20Lib.sol";

import "../BaseMoneyMarket.sol";
import "./dependencies/IEulerVault.sol";
import "./dependencies/IEthereumVaultConnector.sol";
import "./dependencies/IRewardStreams.sol";

import "./EulerReverseLookup.sol";
import "./EulerRewardsOperator.sol";

contract EulerMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for *;
    using SafeERC20 for IERC20;

    bool public constant override NEEDS_ACCOUNT = true;

    IEthereumVaultConnector public immutable evc;
    EulerReverseLookup public immutable reverseLookup;
    IRewardStreams public immutable rewards;
    EulerRewardsOperator public immutable rewardOperator;

    constructor(
        IContango _contango,
        IEthereumVaultConnector _evc,
        IRewardStreams _rewards,
        EulerReverseLookup _reverseLookup,
        EulerRewardsOperator _rewardOperator
    ) BaseMoneyMarket(MM_EULER, _contango) {
        evc = _evc;
        rewards = _rewards;
        reverseLookup = _reverseLookup;
        rewardOperator = _rewardOperator;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        require(positionId.isPerp(), InvalidExpiry());

        IEulerVault baseVault = reverseLookup.base(positionId);
        IEulerVault quoteVault = reverseLookup.quote(positionId);

        collateralAsset.forceApprove(address(baseVault), type(uint256).max);
        debtAsset.forceApprove(address(quoteVault), type(uint256).max);
        // Enable base currency as collateral
        evc.enableCollateral(address(this), baseVault);
        // Make quote currency the borrowable asset for this account
        evc.enableController(address(this), quoteVault);
        // Add custom operator so we can manage rewards related operations on behalf of the account
        evc.setAccountOperator(address(this), address(rewardOperator), true);
        // Enable callback so rewards streams get called when the balance of the account changes
        baseVault.enableBalanceForwarder();
        // Enable all live rewards for this account
        rewardOperator.enableLiveRewards(positionId);
    }

    function _collateralBalance(PositionId positionId, IERC20) internal view override returns (uint256 balance) {
        IEulerVault vault = reverseLookup.base(positionId);
        return vault.convertToAssets(vault.balanceOf(address(this)));
    }

    function _debtBalance(PositionId positionId, IERC20) internal view override returns (uint256 balance) {
        return reverseLookup.quote(positionId).debtOf(address(this));
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        asset.transferOut(payer, address(this), amount);
        IEulerVault vault = reverseLookup.base(positionId);
        uint256 sharesDeposited = vault.deposit(amount, address(this));
        actualAmount = vault.convertToAssets(sharesDeposited);
    }

    function _borrow(PositionId positionId, IERC20, uint256 amount, address to, uint256) internal override returns (uint256 actualAmount) {
        actualAmount = reverseLookup.quote(positionId).borrow(amount, to);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        override
        returns (uint256 actualAmount)
    {
        amount = asset.transferOut(payer, address(this), Math.min(amount, debt));
        actualAmount = reverseLookup.quote(positionId).repay(amount, address(this));
    }

    function _withdraw(PositionId positionId, IERC20, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        IEulerVault vault = reverseLookup.base(positionId);
        uint256 sharesWithdrawn = vault.withdraw(amount, to, address(this));
        actualAmount = vault.convertToAssets(sharesWithdrawn);
    }

    function _claimRewards(PositionId positionId, IERC20, IERC20, address to) internal virtual override {
        rewardOperator.claimAllRewards(positionId, to);
    }

}

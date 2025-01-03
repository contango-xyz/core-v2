//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "./dependencies/IExactlyRewardsController.sol";
import "./ExactlyReverseLookup.sol";

import "../BaseMoneyMarket.sol";

contract ExactlyMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for IERC20;
    using SafeERC20 for IERC20;
    using Math for uint256;

    bool public constant override NEEDS_ACCOUNT = true;

    ExactlyReverseLookup public immutable reverseLookup;
    IAuditor public immutable auditor;
    IExactlyRewardsController public immutable rewardsController;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        ExactlyReverseLookup _reverseLookup,
        IExactlyRewardsController _rewardsController
    ) BaseMoneyMarket(_moneyMarketId, _contango) {
        reverseLookup = _reverseLookup;
        auditor = _reverseLookup.auditor();
        rewardsController = _rewardsController;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();
        auditor.enterMarket(reverseLookup.market(collateralAsset));
        collateralAsset.forceApprove(address(reverseLookup.market(collateralAsset)), type(uint256).max);
        debtAsset.forceApprove(address(reverseLookup.market(debtAsset)), type(uint256).max);
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer, uint256) internal override returns (uint256 actualAmount) {
        asset.transferOut(payer, address(this), amount);
        reverseLookup.market(asset).deposit(amount, address(this));
        actualAmount = amount;
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to, uint256) internal override returns (uint256 actualAmount) {
        reverseLookup.market(asset).withdraw(amount, to, address(this));
        actualAmount = amount;
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to, uint256) internal override returns (uint256 actualAmount) {
        reverseLookup.market(asset).borrow(amount, to, address(this));
        actualAmount = amount;
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        override
        returns (uint256 actualAmount)
    {
        IExactlyMarket market = reverseLookup.market(asset);
        if (market.previewRepay(amount) == 0) return 0;
        asset.transferOut(payer, address(this), Math.min(amount, debt));

        (actualAmount,) = market.repay(amount, address(this));
    }

    function _claimRewards(PositionId, IERC20, IERC20, address to) internal override {
        rewardsController.claimAll(to);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view override returns (uint256 balance) {
        IExactlyMarket collateralMarket = reverseLookup.market(asset);
        return collateralMarket.convertToAssets(collateralMarket.balanceOf(address(this)));
    }

    function _debtBalance(PositionId, IERC20 asset) internal view override returns (uint256 balance) {
        balance = reverseLookup.market(asset).previewDebt(address(this));
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./SiloBase.sol";
import "../BaseMoneyMarket.sol";
import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";
import { MM_SILO } from "script/constants.sol";

contract SiloMoneyMarket is BaseMoneyMarket, SiloBase {

    using SafeERC20 for *;
    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;
    bool public constant COLLATERAL_ONLY = false;

    ISilo public silo;

    constructor(IContango _contango) BaseMoneyMarket(MM_SILO, _contango) { }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        silo = getSilo(collateralAsset, debtAsset);
        collateralAsset.forceApprove(address(silo), type(uint256).max);
        debtAsset.forceApprove(address(silo), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal virtual override returns (uint256 balance) {
        silo.accrueInterest(asset);
        balance = LENS.collateralBalanceOfUnderlying(silo, asset, address(this));
    }

    function _debtBalance(PositionId, IERC20 asset) internal virtual returns (uint256 balance) {
        silo.accrueInterest(asset);
        balance = LENS.getBorrowAmount(silo, asset, address(this), block.timestamp);
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer) internal virtual override returns (uint256 actualAmount) {
        (actualAmount,) = silo.deposit(asset, asset.transferOut(payer, address(this), amount), COLLATERAL_ONLY);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to) internal virtual override returns (uint256 actualAmount) {
        (actualAmount,) = silo.borrow(asset, amount);
        asset.transferOut(address(this), to, actualAmount);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, _debtBalance(positionId, asset));
        if (actualAmount > 0) silo.repay(asset, asset.transferOut(payer, address(this), actualAmount));
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        if (amount == _collateralBalance(positionId, asset)) amount = type(uint256).max;
        (actualAmount,) = silo.withdraw(asset, amount, COLLATERAL_ONLY);
        asset.transferOut(address(this), to, actualAmount);
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        INCENTIVES_CONTROLLER.claimRewards(
            toArray(silo.assetStorage(collateralAsset).collateralToken, silo.assetStorage(debtAsset).debtToken), type(uint256).max, to
        );
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./SiloBase.sol";
import "../BaseMoneyMarket.sol";
import "../../libraries/ERC20Lib.sol";
import { toArray } from "../../libraries/Arrays.sol";

contract SiloMoneyMarket is BaseMoneyMarket, SiloBase {

    using SafeERC20 for *;
    using ERC20Lib for *;
    using { isCollateralOnly } for PositionId;

    bool public constant override NEEDS_ACCOUNT = true;

    ISilo public silo;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, ISiloLens _lens, ISilo _wstEthSilo, IERC20 _weth, IERC20 _stablecoin)
        BaseMoneyMarket(_moneyMarketId, _contango)
        SiloBase(_lens, _wstEthSilo, _weth, _stablecoin)
    { }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        silo = getSilo(collateralAsset, debtAsset);
        collateralAsset.forceApprove(address(silo), type(uint256).max);
        debtAsset.forceApprove(address(silo), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal virtual override returns (uint256 balance) {
        silo.accrueInterest(asset);
        balance = lens.collateralBalanceOfUnderlying(silo, asset, address(this));
    }

    function _debtBalance(PositionId, IERC20 asset) internal virtual override returns (uint256 balance) {
        silo.accrueInterest(asset);
        balance = lens.getBorrowAmount(silo, asset, address(this), block.timestamp);
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        (actualAmount,) = silo.deposit(asset, asset.transferOut(payer, address(this), amount), positionId.isCollateralOnly());
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        (actualAmount,) = silo.borrow(asset, amount);
        asset.transferOut(address(this), to, actualAmount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, debt);
        if (actualAmount > 0) silo.repay(asset, asset.transferOut(payer, address(this), actualAmount));
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256 balance)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        if (amount == balance) amount = type(uint256).max;
        (actualAmount,) = silo.withdraw(asset, amount, positionId.isCollateralOnly());
        asset.transferOut(address(this), to, actualAmount);
    }

    function _claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        ISilo _silo = silo;
        ISiloIncentivesController incentivesController = repository.getNotificationReceiver(_silo);

        if (address(incentivesController) == address(0)) return;

        IERC20 collateralToken = positionId.isCollateralOnly()
            ? _silo.assetStorage(collateralAsset).collateralOnlyToken
            : _silo.assetStorage(collateralAsset).collateralToken;
        uint256 amount =
            incentivesController.claimRewards(toArray(collateralToken, _silo.assetStorage(debtAsset).debtToken), type(uint256).max, to);

        if (amount > 0) emit RewardsClaimed(positionId, incentivesController.REWARD_TOKEN(), to, amount);
    }

}

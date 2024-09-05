//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./AaveMoneyMarketWithoutFlashBorrow.sol";
import "./dependencies/Spark.sol";

contract SparkMoneyMarket is AaveMoneyMarketWithoutFlashBorrow {

    using ERC20Lib for *;

    uint256 public constant DAI_USDC_UNIT_DIFF = 1e12;

    IERC20 public immutable dai;
    ISDAI public immutable sDAI;
    IERC20 public immutable usdc;
    IDssPsm public immutable psm;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController,
        IERC20 _dai,
        ISDAI _sDAI,
        IERC20 _usdc,
        IDssPsm _psm
    ) AaveMoneyMarketWithoutFlashBorrow(_moneyMarketId, _contango, _pool, _dataProvider, _rewardsController) {
        dai = _dai;
        sDAI = _sDAI;
        usdc = _usdc;
        psm = _psm;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (debtAsset == usdc || collateralAsset == usdc) {
            dai.infiniteApproval(address(psm));
            usdc.infiniteApproval(psm.gemJoin());
        }

        if (debtAsset == usdc) debtAsset = dai;

        if (collateralAsset == usdc || collateralAsset == dai) {
            dai.infiniteApproval(address(sDAI));
            collateralAsset = sDAI;
        }

        super._initialise(positionId, collateralAsset, debtAsset);
    }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal view virtual override returns (uint256 balance) {
        if (asset == usdc || asset == dai) {
            balance = sDAI.previewRedeem(super._collateralBalance(positionId, sDAI));
            if (asset == usdc) balance /= DAI_USDC_UNIT_DIFF;
        } else {
            balance = super._collateralBalance(positionId, asset);
        }
    }

    function _debtBalance(PositionId positionId, IERC20 asset) internal view virtual override returns (uint256 balance) {
        balance = asset == usdc
            ? (super._debtBalance(positionId, dai) + DAI_USDC_UNIT_DIFF - 1) / DAI_USDC_UNIT_DIFF
            : super._debtBalance(positionId, asset);
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        if (asset == usdc || asset == dai) {
            actualAmount = asset.transferOut(payer, address(this), amount);

            if (asset == usdc) {
                psm.sellGem(address(this), amount);
                amount *= DAI_USDC_UNIT_DIFF;
            }

            super._lend(positionId, sDAI, sDAI.deposit(amount, address(this)), address(this));
        } else {
            actualAmount = super._lend(positionId, asset, amount, payer);
        }
    }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        if (asset == usdc) {
            actualAmount = super._borrow(positionId, dai, amount * DAI_USDC_UNIT_DIFF, address(this)) / DAI_USDC_UNIT_DIFF;
            psm.buyGem(to, amount);
        } else {
            actualAmount = super._borrow(positionId, asset, amount, to);
        }
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        if (asset == usdc) {
            actualAmount = Math.min(amount, _debtBalance(positionId, asset));
            asset.transferOut(payer, address(this), actualAmount);
            psm.sellGem(address(this), actualAmount);
            super._repay(positionId, dai, actualAmount * DAI_USDC_UNIT_DIFF, address(this));
        } else {
            actualAmount = super._repay(positionId, asset, amount, payer);
        }
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        if (asset == usdc || asset == dai) {
            actualAmount = sDAI.redeem({
                shares: super._withdraw(
                    positionId, sDAI, sDAI.previewWithdraw(asset == usdc ? amount * DAI_USDC_UNIT_DIFF : amount), address(this)
                ),
                receiver: asset == usdc ? address(this) : to,
                owner: address(this)
            });

            if (asset == usdc) {
                actualAmount /= DAI_USDC_UNIT_DIFF;
                psm.buyGem(to, actualAmount);
            }
        } else {
            actualAmount = super._withdraw(positionId, asset, amount, to);
        }
    }

}

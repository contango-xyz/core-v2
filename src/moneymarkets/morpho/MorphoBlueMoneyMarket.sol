//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IMorpho.sol";
import { SharesMathLib } from "./dependencies/SharesMathLib.sol";

import "../BaseMoneyMarket.sol";
import "./MorphoBlueReverseLookup.sol";
import "../../libraries/ERC20Lib.sol";

contract MorphoBlueMoneyMarket is BaseMoneyMarket {

    using SafeERC20 for *;
    using ERC20Lib for *;
    using SharesMathLib for *;

    bool public constant override NEEDS_ACCOUNT = true;

    IMorpho public immutable morpho;
    MorphoBlueReverseLookup public immutable reverseLookup;
    IERC20 public immutable ena;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, IMorpho _morpho, MorphoBlueReverseLookup _reverseLookup, IERC20 _ena)
        BaseMoneyMarket(_moneyMarketId, _contango)
    {
        morpho = _morpho;
        reverseLookup = _reverseLookup;
        ena = _ena;
    }

    // ====== IMoneyMarket =======

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        collateralAsset.forceApprove(address(morpho), type(uint256).max);
        debtAsset.forceApprove(address(morpho), type(uint256).max);
    }

    function _collateralBalance(PositionId positionId, IERC20) internal view virtual override returns (uint256 balance) {
        balance = morpho.position(reverseLookup.marketId(positionId.getPayload()), address(this)).collateral;
    }

    function _debtBalance(PositionId positionId, IERC20) internal virtual override returns (uint256 balance) {
        MorphoMarketId marketId = reverseLookup.marketId(positionId.getPayload());
        morpho.accrueInterest(morpho.idToMarketParams(marketId)); // Accrue interest before loading the market state
        Market memory market = morpho.market(marketId);
        Position memory position = morpho.position(marketId, address(this));
        balance = position.borrowShares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        morpho.supplyCollateral({
            marketParams: morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload())),
            assets: actualAmount = asset.transferOut(payer, address(this), amount),
            onBehalf: address(this),
            data: ""
        });
    }

    function _borrow(PositionId positionId, IERC20, uint256 amount, address to, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        (actualAmount,) = morpho.borrow({
            marketParams: morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload())),
            assets: amount,
            shares: 0,
            onBehalf: address(this),
            receiver: to
        });
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        MorphoMarketId marketId = reverseLookup.marketId(positionId.getPayload());
        Market memory market = morpho.market(marketId);

        // Parent called _debtBalance and thus interest is accrued
        uint256 borrowShares = morpho.position(marketId, address(this)).borrowShares;
        uint256 actualShares = Math.min(amount.toSharesDown(market.totalBorrowAssets, market.totalBorrowShares), borrowShares);

        if (actualShares > 0) {
            asset.transferOut(
                payer,
                address(this),
                actualShares == borrowShares ? actualShares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares) : amount
            );

            (actualAmount,) = morpho.repay({
                marketParams: morpho.idToMarketParams(marketId),
                assets: 0,
                shares: actualShares,
                onBehalf: address(this),
                data: ""
            });
        }
    }

    function _withdraw(PositionId positionId, IERC20, uint256 amount, address to, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        morpho.withdrawCollateral({
            marketParams: morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload())),
            assets: actualAmount = amount,
            onBehalf: address(this),
            receiver: to
        });
    }

}

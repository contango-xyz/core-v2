//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "../BaseMoneyMarketView.sol";
import { MM_COMET } from "script/constants.sol";

import "./dependencies/IComet.sol";
import "./dependencies/ICometRewards.sol";
import "./CometReverseLookup.sol";

contract CometMoneyMarketView is BaseMoneyMarketView {

    using ERC20Lib for IERC20;
    using Math for uint256;

    error OracleNotFound(IERC20 asset);

    CometReverseLookup public immutable reverseLookup;
    ICometRewards public immutable cometRewards;

    constructor(
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        CometReverseLookup _reverseLookup,
        ICometRewards _cometRewards
    ) BaseMoneyMarketView(MM_COMET, "Comet", _contango, _nativeToken, _nativeUsdOracle) {
        reverseLookup = _reverseLookup;
        cometRewards = _cometRewards;
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20) internal view override returns (Balances memory balances_) {
        address account = _account(positionId);
        IComet comet = reverseLookup.comet(positionId.getPayload());
        balances_.collateral = comet.collateralBalanceOf(account, collateralAsset);
        balances_.debt = comet.borrowBalanceOf(account);
    }

    function _prices(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (Prices memory prices_)
    {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        prices_.collateral = comet.getPrice(comet.getAssetInfoByAddress(collateralAsset).priceFeed);
        prices_.debt = comet.getPrice(comet.baseTokenPriceFeed());
        prices_.unit = 1e8;
    }

    function _thresholds(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        IComet.AssetInfo memory assetInfo = comet.getAssetInfoByAddress(collateralAsset);
        ltv = assetInfo.borrowCollateralFactor;
        liquidationThreshold = assetInfo.liquidateCollateralFactor;
    }

    function _liquidity(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        IComet comet = reverseLookup.comet(positionId.getPayload());

        uint256 totalSupply = comet.totalSupply();
        uint256 totalBorrow = comet.totalBorrow();
        borrowing = totalSupply > totalBorrow ? totalSupply - totalBorrow : 0;

        uint256 supplyCap = comet.getAssetInfoByAddress(collateralAsset).supplyCap;
        uint256 supplied = comet.totalsCollateral(collateralAsset).totalSupplyAsset;

        lending = supplyCap > supplied ? supplyCap - supplied : 0;
    }

    function _rates(PositionId positionId, IERC20, IERC20) internal view virtual override returns (uint256 borrowing, uint256 lending) {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        borrowing = _apy({ rate: comet.getBorrowRate(comet.getUtilization()), perSeconds: 1 });
        lending = 0;
    }

    function _availableActions(PositionId positionId, IERC20, IERC20)
        internal
        view
        override
        returns (AvailableActions[] memory available)
    {
        IComet comet = reverseLookup.comet(positionId.getPayload());

        available = new AvailableActions[](ACTIONS);
        uint256 count;

        if (!comet.isSupplyPaused()) {
            available[count++] = AvailableActions.Lend;
            available[count++] = AvailableActions.Repay;
        }
        if (!comet.isWithdrawPaused()) {
            available[count++] = AvailableActions.Withdraw;
            available[count++] = AvailableActions.Borrow;
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(available, count)
        }
    }

    function _limits(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Limits memory limits_)
    {
        limits_ = super._limits(positionId, collateralAsset, debtAsset);
        IComet comet = reverseLookup.comet(positionId.getPayload());
        limits_.minBorrowing = comet.baseBorrowMin();
        limits_.minBorrowingForRewards = comet.baseMinForRewards();
    }

    struct IRMData {
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 borrowKink;
        uint256 borrowPerSecondInterestRateSlopeLow;
        uint256 borrowPerSecondInterestRateSlopeHigh;
        uint256 borrowPerSecondInterestRateBase;
    }

    struct RewardsData {
        uint256 baseTrackingBorrowSpeed;
        uint256 baseIndexScale;
        uint256 baseAccrualScale;
        uint256 totalBorrow;
        uint256 claimable;
        TokenData token;
    }

    struct RawData {
        IRMData irmData;
        RewardsData rewardsData;
    }

    // This function is here to make our life easier on the wagmi/viem side
    function rawData(PositionId positionId) public returns (RawData memory data) {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        data.irmData = IRMData({
            totalSupply: comet.totalSupply(),
            totalBorrow: comet.totalBorrow(),
            borrowKink: comet.borrowKink(),
            borrowPerSecondInterestRateSlopeLow: comet.borrowPerSecondInterestRateSlopeLow(),
            borrowPerSecondInterestRateSlopeHigh: comet.borrowPerSecondInterestRateSlopeHigh(),
            borrowPerSecondInterestRateBase: comet.borrowPerSecondInterestRateBase()
        });

        data.rewardsData = RewardsData({
            baseTrackingBorrowSpeed: comet.baseTrackingBorrowSpeed(),
            baseIndexScale: comet.baseIndexScale(),
            baseAccrualScale: comet.baseAccrualScale(),
            totalBorrow: comet.totalBorrow(),
            claimable: cometRewards.getRewardOwed(comet, _account(positionId)).owed,
            token: _asTokenData(cometRewards.rewardConfig(comet).token)
        });
    }

    function _irmRaw(PositionId positionId, IERC20, IERC20) internal virtual override returns (bytes memory data) {
        data = abi.encode(rawData(positionId));
    }

    // So these functions can't be implemented
    // The reason why they are not made to revert is because Solidity would thrown an "Unreachable code" error
    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) { }
    function _oracleUnit() internal view virtual override returns (uint256) { }
    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) { }
    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) { }

}

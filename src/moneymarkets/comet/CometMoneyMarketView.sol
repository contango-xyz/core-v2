//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

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

    CometReverseLookup public immutable reverseLookup;
    ICometRewards public immutable cometRewards;
    IAggregatorV2V3 public immutable compOracle;

    constructor(
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        CometReverseLookup _reverseLookup,
        ICometRewards _cometRewards,
        IAggregatorV2V3 _compOracle
    ) BaseMoneyMarketView(MM_COMET, "Comet", _contango, _nativeToken, _nativeUsdOracle) {
        reverseLookup = _reverseLookup;
        cometRewards = _cometRewards;
        compOracle = _compOracle;
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20) internal view override returns (Balances memory balances_) {
        address account = _account(positionId);
        IComet comet = reverseLookup.comet(positionId.getPayload());
        balances_.collateral = comet.userCollateral(account, collateralAsset).balance;
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

    // Comet's Oracles don't follow the pattern of returning the price of the base currency in USD or ETH
    // Instead, they return the price of the collateral in the loan token
    // So these 2 functions can't be implemented
    // The reason why they are not made to revert is because Solidity would thrown an "Unreachable code" error
    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) { }
    function _oracleUnit() internal view virtual override returns (uint256) { }

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
        borrowing = comet.totalSupply() - comet.totalBorrow();

        uint256 supplyCap = comet.getAssetInfoByAddress(collateralAsset).supplyCap;
        uint256 supplied = comet.totalsCollateral(collateralAsset).totalSupplyAsset;

        lending = supplyCap > supplied ? supplyCap - supplied : 0;
    }

    function _rates(PositionId positionId, IERC20, IERC20) internal view virtual override returns (uint256 borrowing, uint256 lending) {
        IComet comet = reverseLookup.comet(positionId.getPayload());
        borrowing = comet.getBorrowRate(comet.getUtilization()) * 365 days;
        lending = 0;
    }

    function _rewards(PositionId positionId, IERC20, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        lending = new Reward[](0);
        IComet comet = reverseLookup.comet(positionId.getPayload());

        uint256 baseTrackingBorrowSpeed = comet.baseTrackingBorrowSpeed();
        if (baseTrackingBorrowSpeed == 0) return (new Reward[](0), lending);

        borrowing = new Reward[](1);
        borrowing[0].token = asTokenData(cometRewards.rewardConfig(comet).token);
        borrowing[0].claimable = cometRewards.getRewardOwed(comet, _account(positionId)).owed;
        borrowing[0].usdPrice = uint256(compOracle.latestAnswer()) * 1e10;

        uint256 unit = 10 ** debtAsset.decimals();
        uint256 accrualDescaleFactor = unit / 1e6;
        baseTrackingBorrowSpeed = 1e18 * comet.baseTrackingBorrowSpeed() / comet.trackingIndexScale() / accrualDescaleFactor;
        uint256 priceOfBorrow = comet.getPrice(comet.baseTokenPriceFeed()) * 1e10;
        uint256 valueOfBorrow = comet.totalBorrow() * priceOfBorrow / unit;
        uint256 yearlyReward = baseTrackingBorrowSpeed * 365 days;
        uint256 valueOfReward = yearlyReward * borrowing[0].usdPrice / 1e18;

        borrowing[0].rate = valueOfReward * 1e18 / valueOfBorrow;
    }

}

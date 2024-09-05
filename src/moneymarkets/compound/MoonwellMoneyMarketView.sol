//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { ISolidlyPool } from "../../dependencies/Solidly.sol";
import "./CompoundMoneyMarketView.sol";
import "./dependencies/Moonwell.sol";
import { MM_MOONWELL } from "script/constants.sol";

contract MoonwellMoneyMarketView is CompoundMoneyMarketView {

    IERC20 public immutable bridgedWell;
    IERC20 public immutable nativeWell;
    IMoonwellMultiRewardDistributor public immutable rewardsDistributor;

    ISolidlyPool public immutable bridgedWellTokenOracle;
    ISolidlyPool public immutable nativeWellTokenOracle;

    constructor(
        IContango _contango,
        CompoundReverseLookup _reverseLookup,
        address _bridgedWellTokenOracle,
        IERC20 _bridgedWell,
        address _nativeWellTokenOracle,
        IERC20 _nativeWell,
        IAggregatorV2V3 _nativeUsdOracle
    ) CompoundMoneyMarketView(MM_MOONWELL, "Moonwell", _contango, _reverseLookup, _nativeWellTokenOracle, _nativeUsdOracle) {
        bridgedWell = _bridgedWell;
        nativeWell = _nativeWell;
        rewardsDistributor = IMoonwellComptroller(address(_reverseLookup.comptroller())).rewardDistributor();
        bridgedWellTokenOracle = ISolidlyPool(_bridgedWellTokenOracle);
        nativeWellTokenOracle = ISolidlyPool(_nativeWellTokenOracle);
    }

    function _oraclePrice(IERC20 asset) internal view override returns (uint256 price) {
        price = IMoonwellOracle(comptroller.oracle()).getUnderlyingPrice(_cToken(asset));
        uint256 decimals = asset.decimals();
        if (decimals < 18) price = price / 10 ** (18 - decimals);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return WAD;
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20 /* debtAsset */ )
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (, ltv) = IMoonwellComptroller(address(comptroller)).markets(_cToken(collateralAsset));
        liquidationThreshold = ltv;
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _apy({ rate: _mToken(debtAsset).borrowRatePerTimestamp(), perSeconds: _rateFrequency() });
        lending = _apy({ rate: _mToken(collateralAsset).supplyRatePerTimestamp(), perSeconds: _rateFrequency() });
    }

    function _cTokenBalance(IERC20 asset, ICToken cToken) internal view virtual override returns (uint256) {
        return asset.balanceOf(address(cToken));
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual override returns (uint256) {
        ICToken cToken = _cToken(asset);
        uint256 cap = IMoonwellComptroller(address(comptroller)).supplyCaps(cToken);
        if (cap == 0) return asset.totalSupply();

        uint256 supplied = cToken.getCash() + cToken.totalBorrows() - cToken.totalReserves();
        if (supplied > cap) return 0;
        return cap - supplied;
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        borrowing = _allRewards(positionId, debtAsset, true);
        lending = _allRewards(positionId, collateralAsset, false);
    }

    function _interestRateModelIrmData(ICToken cToken)
        internal
        view
        override
        returns (uint256 baseRatePerBlock, uint256 jumpMultiplierPerBlock, uint256 multiplierPerBlock, uint256 kink)
    {
        ILegacyJumpRateModelV2 irm = cToken.interestRateModel();
        baseRatePerBlock = irm.baseRatePerTimestamp();
        jumpMultiplierPerBlock = irm.jumpMultiplierPerTimestamp();
        multiplierPerBlock = irm.multiplierPerTimestamp();
        kink = irm.kink();
    }

    function _allRewards(PositionId positionId, IERC20 asset, bool borrowing) internal view returns (Reward[] memory rewards_) {
        ICToken cToken = _cToken(asset);
        IMoonwellMultiRewardDistributor.MarketConfig[] memory markets = rewardsDistributor.getAllMarketConfigs(cToken);

        Reward[] memory tmp = new Reward[](markets.length);
        uint256 count;
        for (uint256 i = 0; i < markets.length; i++) {
            IMoonwellMultiRewardDistributor.MarketConfig memory market = markets[i];
            Reward memory reward = _asRewards(positionId, asset, cToken, market, borrowing, i);

            if (
                reward.claimable == 0
                    && (
                        market.endTime < block.timestamp || borrowing && market.borrowEmissionsPerSec < 2
                            || !borrowing && market.supplyEmissionsPerSec < 2
                    )
            ) continue;

            tmp[count++] = reward;
        }

        rewards_ = new Reward[](count);
        uint256 j;
        for (uint256 i = 0; i < tmp.length; i++) {
            Reward memory reward = tmp[i];
            if (reward.rate > 1 || reward.claimable > 0) rewards_[j++] = tmp[i];
        }
    }

    function _asRewards(
        PositionId positionId,
        IERC20 asset,
        ICToken cToken,
        IMoonwellMultiRewardDistributor.MarketConfig memory config,
        bool borrowing,
        uint256 idx
    ) internal view returns (Reward memory rewards_) {
        IERC20 rewardsToken = config.emissionToken;

        rewards_.usdPrice = _rewardsTokenUSDPrice(rewardsToken);
        rewards_.token = _asTokenData(rewardsToken);

        uint256 assetPrice = priceInUSD(asset);

        if (borrowing) {
            {
                uint256 unitDelta = rewardsToken.decimals() < 18 ? 10 ** (18 - rewardsToken.decimals()) : 1;
                uint256 emissionsPerYear = config.borrowEmissionsPerSec * 365 days * unitDelta;
                uint256 valueOfEmissions = emissionsPerYear * rewards_.usdPrice / WAD;

                unitDelta = asset.decimals() < 18 ? 10 ** (18 - asset.decimals()) : 1;
                uint256 assetsBorrowed = cToken.totalBorrows() * unitDelta;
                uint256 valueOfAssetsBorrowed = assetPrice * assetsBorrowed / (10 ** (asset.decimals()));

                rewards_.rate = valueOfEmissions * WAD / valueOfAssetsBorrowed;
            }

            rewards_.claimable = positionId.getNumber() > 0
                ? rewardsDistributor.getOutstandingRewardsForUser(cToken, _account(positionId))[idx].borrowSide
                : 0;
        } else {
            {
                uint256 unitDelta = rewardsToken.decimals() < 18 ? 10 ** (18 - rewardsToken.decimals()) : 1;
                uint256 emissionsPerYear = config.supplyEmissionsPerSec * 365 days * unitDelta;
                uint256 valueOfEmissions = emissionsPerYear * rewards_.usdPrice / WAD;

                unitDelta = asset.decimals() < 18 ? 10 ** (18 - asset.decimals()) : 1;
                uint256 assetSupplied = (cToken.getCash() + cToken.totalBorrows() - cToken.totalReserves()) * unitDelta;
                uint256 valueOfAssetsSupplied = assetPrice * assetSupplied / WAD;

                rewards_.rate = valueOfEmissions * WAD / valueOfAssetsSupplied;
            }

            rewards_.claimable = positionId.getNumber() > 0
                ? rewardsDistributor.getOutstandingRewardsForUser(cToken, _account(positionId))[idx].supplySide
                : 0;
        }
    }

    function _rewardsTokenUSDPrice(IERC20 token) internal view virtual returns (uint256) {
        if (token == bridgedWell) {
            uint256 wellEth = bridgedWellTokenOracle.getAmountOut(WAD, bridgedWell);
            uint256 ethUsd = uint256(nativeUsdOracle.latestAnswer());
            return wellEth * ethUsd / 1e8;
        } else if (token == nativeWell) {
            uint256 wellEth = nativeWellTokenOracle.getAmountOut(WAD, nativeWell);
            uint256 ethUsd = uint256(nativeUsdOracle.latestAnswer());
            return wellEth * ethUsd / 1e8;
        } else {
            return priceInUSD(token);
        }
    }

    function _getBlockNumber() internal view virtual override returns (uint256) {
        // Moonwell uses timestamp instead of blocks
        return block.timestamp;
    }

    function _mToken(IERC20 asset) internal view virtual returns (IMToken) {
        return IMToken(address(reverseLookup.cToken(asset)));
    }

    function _blocksPerDay() internal pure virtual override returns (uint256) {
        // Moonwell uses timestamp instead of blocks, so Blocks Per Day is actually Seconds Per Day
        return 1 days;
    }

    function _rateFrequency() internal pure virtual override returns (uint256) {
        return 1;
    }

}

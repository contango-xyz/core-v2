//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ISolidlyPool } from "../../dependencies/Solidly.sol";
import "./CompoundMoneyMarketView.sol";
import "./dependencies/IPriceOracleProxyETH.sol";
import { MM_LODESTAR } from "script/constants.sol";

contract LodestarMoneyMarketView is CompoundMoneyMarketView {

    IAggregatorV2V3 public immutable arbOracle;
    IERC20 public immutable arbToken;

    constructor(
        IContango _contango,
        CompoundReverseLookup _reverseLookup,
        address _rewardsTokenOracle,
        IAggregatorV2V3 _arbOracle,
        IERC20 _arbToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) CompoundMoneyMarketView(MM_LODESTAR, "Lodestar", _contango, _reverseLookup, _rewardsTokenOracle, _nativeUsdOracle) {
        arbOracle = _arbOracle;
        arbToken = _arbToken;
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        uint256 price = IPriceOracleProxyETH(comptroller.oracle()).getUnderlyingPrice(_cToken(asset));
        uint256 decimals = asset.decimals();
        if (decimals < 18) return price / 10 ** (18 - decimals);
        return price;
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return WAD;
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual override returns (uint256) {
        ICToken cToken = _cToken(asset);
        uint256 cap = ILodestarComptroller(address(comptroller)).supplyCaps(cToken);
        if (cap == 0) return asset.totalSupply();

        uint256 supplied = cToken.totalSupply() * cToken.exchangeRateStored() / WAD;
        if (supplied > cap) return 0;

        return cap - supplied;
    }

    function _rewardsTokenUSDPrice() internal view virtual override returns (uint256) {
        uint256 lodeEth = ISolidlyPool(rewardsTokenOracle).getAmountOut(WAD, comptroller.getCompAddress());
        uint256 ethUsd = uint256(IPriceOracleProxyETH(comptroller.oracle()).ethUsdAggregator().latestAnswer());
        return lodeEth * ethUsd / 1e8;
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        Reward memory reward;
        Reward memory arbRewards = _arbRewards();
        uint256 claimable = arbToken.balanceOf(_account(positionId));

        reward = _asRewards(positionId, debtAsset, true);
        borrowing = reward.rate > 0 ? new Reward[](2) : new Reward[](1);
        borrowing[0] = arbRewards;
        borrowing[0].claimable = claimable / 2;
        if (reward.rate > 0) borrowing[1] = reward;

        reward = _asRewards(positionId, collateralAsset, false);
        lending = reward.rate > 0 ? new Reward[](2) : new Reward[](1);
        lending[0] = arbRewards;
        lending[0].claimable = claimable / 2;
        if (reward.rate > 0) lending[1] = reward;

        _updateClaimable(positionId, borrowing, lending);
    }

    function _arbRewards() internal view virtual returns (Reward memory reward) {
        uint256 ethUsd = uint256(IPriceOracleProxyETH(comptroller.oracle()).ethUsdAggregator().latestAnswer());
        uint256 arbUsd = uint256(arbOracle.latestAnswer());
        uint256 arbEth = arbUsd * 1e8 / ethUsd;

        uint256 totalETHValue;
        ICToken[] memory allMarkets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < allMarkets.length; i++) {
            ICToken cToken = allMarkets[i];
            IERC20 underlying = _cTokenUnderlying(cToken);
            uint256 ethPrice = _oraclePrice(underlying);

            uint256 unit = 10 ** underlying.decimals();
            uint256 valueOfAssetsSupplied = ethPrice * (cToken.totalSupply() * cToken.exchangeRateStored() / WAD) / unit;
            uint256 valueOfAssetsBorrowed = ethPrice * cToken.totalBorrows() / unit;

            totalETHValue += valueOfAssetsSupplied + valueOfAssetsBorrowed;
        }

        reward.token = TokenData(arbToken, arbToken.name(), arbToken.symbol(), arbToken.decimals(), 10 ** arbToken.decimals());
        reward.usdPrice = arbUsd * 10 ** (arbToken.decimals() - 8);

        uint256 weeklyArbRewardsETH = 52_000e18 * arbEth / 1e8;
        uint256 yearlyArbRewardsETH = weeklyArbRewardsETH * 52;
        reward.rate = totalETHValue > 0 ? yearlyArbRewardsETH * WAD / totalETHValue : 0;
    }

    function _cTokenUnderlying(ICToken cToken) internal view returns (IERC20) {
        try cToken.underlying() returns (IERC20 token) {
            return token;
        } catch {
            // fails for native token, e.g. mainnet cETH
            return nativeToken;
        }
    }

}

interface ILodestarComptroller {

    function supplyCaps(ICToken) external view returns (uint256);

}

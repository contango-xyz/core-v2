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

    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) {
        return _oraclePrice(asset);
    }

    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) {
        return _derivePriceInUSD(asset);
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

        uint256 claimable = arbToken.balanceOf(_account(positionId));
        Reward memory arbRewards;
        if (claimable > 0) {
            arbRewards.token = _asTokenData(arbToken);
            arbRewards.usdPrice = uint256(arbOracle.latestAnswer()) * 10 ** (arbToken.decimals() - 8);
            arbRewards.claimable = claimable;
        }

        reward = _asRewards(positionId, collateralAsset, false);
        uint256 length;
        if (arbRewards.claimable > 0) length++;
        if (reward.rate > 0) length++;

        lending = new Reward[](length);
        length = 0;
        if (arbRewards.claimable > 0) lending[length++] = arbRewards;
        if (reward.rate > 0) lending[length++] = reward;

        reward = _asRewards(positionId, debtAsset, true);
        if (reward.rate > 0) {
            borrowing = new Reward[](1);
            borrowing[0] = reward;
        }

        _updateClaimable(positionId, borrowing, lending);
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

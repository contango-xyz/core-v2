//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/Moonwell.sol";
import "./CompoundMoneyMarket.sol";

contract MoonwellMoneyMarket is CompoundMoneyMarket {

    using ERC20Lib for IERC20;

    IWETH9 public immutable nativeToken2;
    IMoonwellMultiRewardDistributor public immutable rewardsDistributor;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, CompoundReverseLookup _reverseLookup, IWETH9 _nativeToken)
        CompoundMoneyMarket(_moneyMarketId, _contango, _reverseLookup, IWETH9(address(0)))
    {
        rewardsDistributor = IMoonwellComptroller(address(_reverseLookup.comptroller())).rewardDistributor();
        nativeToken2 = _nativeToken;
    }

    // Could extract just the claim bit, but then the deploy scrip would want to re-deploy the compound money markets all over the place
    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        ICToken supplyCToken = cToken(collateralAsset);
        ICToken borrowCToken = cToken(debtAsset);

        IMoonwellComptroller(address(comptroller)).claimReward({
            holders: toArray(address(this)),
            cTokens: toArray(address(supplyCToken)),
            borrowers: false,
            suppliers: true
        });
        IMoonwellComptroller(address(comptroller)).claimReward({
            holders: toArray(address(this)),
            cTokens: toArray(address(borrowCToken)),
            borrowers: true,
            suppliers: false
        });

        IMoonwellMultiRewardDistributor.MarketConfig[] memory markets = rewardsDistributor.getAllMarketConfigs(supplyCToken);
        for (uint256 i = 0; i < markets.length; i++) {
            markets[i].emissionToken.transferBalance(to);
        }
        markets = rewardsDistributor.getAllMarketConfigs(borrowCToken);
        for (uint256 i = 0; i < markets.length; i++) {
            markets[i].emissionToken.transferBalance(to);
        }
    }

    // This is what we should have done in the first place, but don't wanna redeploy all Compound money markets
    receive() external payable override {
        nativeToken2.deposit{ value: msg.value }();
    }

}

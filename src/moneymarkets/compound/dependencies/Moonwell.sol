//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ICToken.sol";
import { IAggregatorV2V3 } from "../../../dependencies/Chainlink.sol";

interface IMoonwellOracle {

    function getUnderlyingPrice(ICToken) external view returns (uint256);
    function getFeed(string memory symbol) external view returns (IAggregatorV2V3);

}

interface IMoonwellComptroller {

    function markets(ICToken) external view returns (bool isListed, uint256 collateralFactorMantissa);
    function claimReward(address[] memory holders, address[] memory cTokens, bool borrowers, bool suppliers) external;
    function supplyCaps(ICToken) external view returns (uint256);
    function rewardDistributor() external view returns (IMoonwellMultiRewardDistributor);

}

interface IMToken is ICToken {

    function borrowRatePerTimestamp() external view returns (uint256);
    function supplyRatePerTimestamp() external view returns (uint256);

}

interface IMoonwellMultiRewardDistributor {

    struct MarketConfig {
        address owner;
        IERC20 emissionToken;
        uint256 endTime;
        uint224 supplyGlobalIndex;
        uint32 supplyGlobalTimestamp;
        uint224 borrowGlobalIndex;
        uint32 borrowGlobalTimestamp;
        uint256 supplyEmissionsPerSec;
        uint256 borrowEmissionsPerSec;
    }

    struct RewardInfo {
        IERC20 emissionToken;
        uint256 totalAmount;
        uint256 supplySide;
        uint256 borrowSide;
    }

    struct RewardWithMToken {
        ICToken mToken;
        RewardInfo[] rewards;
    }

    function comptroller() external view returns (address);
    function emissionCap() external view returns (uint256);
    function getAllMarketConfigs(ICToken _mToken) external view returns (MarketConfig[] memory);
    function getConfigForMarket(ICToken _mToken, IERC20 _emissionToken) external view returns (MarketConfig memory);
    function getCurrentEmissionCap() external view returns (uint256);
    function getCurrentOwner(ICToken _mToken, IERC20 _emissionToken) external view returns (address);
    function getGlobalBorrowIndex(ICToken mToken, uint256 index) external view returns (uint256);
    function getGlobalSupplyIndex(ICToken mToken, uint256 index) external view returns (uint256);
    function getOutstandingRewardsForUser(ICToken _mToken, address _user) external view returns (RewardInfo[] memory);
    function getOutstandingRewardsForUser(address _user) external view returns (RewardWithMToken[] memory);
    function initialIndexConstant() external view returns (uint224);
    function marketConfigs(address, uint256) external view returns (MarketConfig memory config);
    function pauseGuardian() external view returns (address);
    function paused() external view returns (bool);

}

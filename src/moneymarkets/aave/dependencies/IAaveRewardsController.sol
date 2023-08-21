//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IAaveRewardsController {

    event Accrued(
        address indexed asset, address indexed reward, address indexed user, uint256 assetIndex, uint256 userIndex, uint256 rewardsAccrued
    );
    event AssetConfigUpdated(
        address indexed asset,
        address indexed reward,
        uint256 oldEmission,
        uint256 newEmission,
        uint256 oldDistributionEnd,
        uint256 newDistributionEnd,
        uint256 assetIndex
    );
    event ClaimerSet(address indexed user, address indexed claimer);
    event RewardOracleUpdated(address indexed reward, address indexed rewardOracle);
    event RewardsClaimed(address indexed user, address indexed reward, address indexed to, address claimer, uint256 amount);
    event TransferStrategyInstalled(address indexed reward, address indexed transferStrategy);

    struct RewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        address asset;
        address reward;
        address transferStrategy;
        address rewardOracle;
    }

    function EMISSION_MANAGER() external view returns (address);
    function REVISION() external view returns (uint256);
    function claimAllRewards(address[] memory assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function claimAllRewardsOnBehalf(address[] memory assets, address user, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function claimAllRewardsToSelf(address[] memory assets)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function claimRewards(address[] memory assets, uint256 amount, address to, address reward) external returns (uint256);
    function claimRewardsOnBehalf(address[] memory assets, uint256 amount, address user, address to, address reward)
        external
        returns (uint256);
    function claimRewardsToSelf(address[] memory assets, uint256 amount, address reward) external returns (uint256);
    function configureAssets(RewardsConfigInput[] memory config) external;
    function getAllUserRewards(address[] memory assets, address user)
        external
        view
        returns (address[] memory rewardsList, uint256[] memory unclaimedAmounts);
    function getAssetDecimals(address asset) external view returns (uint8);
    function getAssetIndex(address asset, address reward) external view returns (uint256, uint256);
    function getClaimer(address user) external view returns (address);
    function getDistributionEnd(address asset, address reward) external view returns (uint256);
    function getEmissionManager() external view returns (address);
    function getRewardOracle(address reward) external view returns (address);
    function getRewardsByAsset(address asset) external view returns (address[] memory);
    function getRewardsData(address asset, address reward) external view returns (uint256, uint256, uint256, uint256);
    function getRewardsList() external view returns (address[] memory);
    function getTransferStrategy(address reward) external view returns (address);
    function getUserAccruedRewards(address user, address reward) external view returns (uint256);
    function getUserAssetIndex(address user, address asset, address reward) external view returns (uint256);
    function getUserRewards(address[] memory assets, address user, address reward) external view returns (uint256);
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;
    function initialize(address) external;
    function setClaimer(address user, address caller) external;
    function setDistributionEnd(address asset, address reward, uint32 newDistributionEnd) external;
    function setEmissionPerSecond(address asset, address[] memory rewards, uint88[] memory newEmissionsPerSecond) external;
    function setRewardOracle(address reward, address rewardOracle) external;
    function setTransferStrategy(address reward, address transferStrategy) external;

}

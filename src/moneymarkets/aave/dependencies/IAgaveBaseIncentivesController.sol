//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IAgaveBaseIncentivesController {

    event AssetConfigUpdated(address indexed asset, uint8 decimals, uint256 emission);
    event AssetIndexUpdated(address indexed asset, uint256 index);
    event BulkClaimerUpdated(address newBulkClaimer);
    event ClaimerSet(address indexed user, address indexed claimer);
    event DistributionEndUpdated(uint256 newDistributionEnd);
    event RewardTokenUpdated(address indexed token);
    event RewardsAccrued(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed to, address indexed claimer, uint256 amount);
    event RewardsVaultUpdated(address indexed vault);
    event UserIndexUpdated(address indexed user, address indexed asset, uint256 index);

    function BULK_CLAIMER() external view returns (address);
    function DISTRIBUTION_END() external view returns (uint256);
    function EMISSION_MANAGER() external view returns (address);
    function PRECISION() external view returns (uint8);
    function PROXY_ADMIN() external view returns (address);
    function REVISION() external view returns (uint256);
    function REWARD_TOKEN() external view returns (IERC20);
    function assets(address)
        external
        view
        returns (uint104 emissionPerSecond, uint104 index, uint40 lastUpdateTimestamp, uint8 decimals, bool disabled);
    function bulkClaimRewardsOnBehalf(address[] memory assets, uint256 amount, address user, address to) external returns (uint256);
    function claimRewards(IERC20[] memory assets, uint256 amount, address to) external returns (uint256);
    function claimRewardsOnBehalf(address[] memory assets, uint256 amount, address user, address to) external returns (uint256);
    function configureAssets(address[] memory assets, uint256[] memory emissionsPerSecond, uint256[] memory assetDecimals) external;
    function disableAssets(address[] memory assets) external;
    function getAssetData(IERC20 asset) external view returns (uint256, uint256, uint8, uint256, bool);
    function getClaimer(address user) external view returns (address);
    function getDistributionEnd() external view returns (uint256);
    function getRewardsBalance(IERC20[] memory assets, address user) external view returns (uint256);
    function getRewardsVault() external view returns (address);
    function getUserAssetData(address user, address asset) external view returns (uint256);
    function getUserUnclaimedRewards(address _user) external view returns (uint256);
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;
    function initialize(address rewardsVault) external;
    function newRewardTokenAdjustmentAmount() external view returns (uint256);
    function newRewardTokenAdjustmentMultiplier() external view returns (bool);
    function setBulkClaimer(address bulkClaimer) external;
    function setClaimer(address user, address caller) external;
    function setDistributionEnd(uint256 distributionEnd) external;
    function setRewardToken(address rewardToken) external;
    function setRewardTokenAdjustment(bool rewardTokenAdjustmentMultiplier, uint256 rewardTokenAdjustmentAmount) external;
    function setRewardsVault(address rewardsVault) external;

}

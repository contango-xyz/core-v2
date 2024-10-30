// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IEulerVault.sol";

interface IRewardStreams {

    /// @notice The maximumum number of reward tokens enabled per account and rewarded token.
    function MAX_REWARDS_ENABLED() external view returns (uint256);

    /// @notice Enable reward token.
    /// @dev There can be at most MAX_REWARDS_ENABLED rewards enabled for the reward token and the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return Whether the reward token was enabled.
    function enableReward(IEulerVault rewarded, IERC20 reward) external returns (bool);

    /// @notice Disable reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return Whether the reward token was disabled.
    function disableReward(IEulerVault rewarded, IERC20 reward, bool forfeitRecentReward) external returns (bool);

    /// @notice Returns enabled reward tokens for a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return An array of addresses representing the enabled reward tokens.
    function enabledRewards(address account, IEulerVault rewarded) external view returns (address[] memory);

    /// @notice Claims earned reward.
    /// @dev Rewards are only transferred to the recipient if the recipient is non-zero.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the claimed reward tokens.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return The amount of the claimed reward tokens.
    function claimReward(IEulerVault rewarded, IERC20 reward, address recipient, bool forfeitRecentReward) external returns (uint256);

    /// @notice Returns the earned reward token amount for a specific account and rewarded token.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return The earned reward token amount for the account and rewarded token.
    function earnedReward(address account, IEulerVault rewarded, IERC20 reward, bool forfeitRecentReward) external view returns (uint256);

    function currentEpoch() external view returns (uint48);

    // For testing purposes

    /// @notice Registers a new reward stream.
    /// @param rewarded The rewarded token.
    /// @param reward The reward token.
    /// @param startEpoch The epoch to start the reward stream from.
    /// @param rewardAmounts The reward token amounts for each epoch of the reward stream.
    function registerReward(IERC20 rewarded, IERC20 reward, uint48 startEpoch, uint128[] calldata rewardAmounts) external;

}

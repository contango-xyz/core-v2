// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRewardFaucet {

    event DistributePast(IERC20 token, uint256 amount, uint256 weekStart);
    event ExactWeekDistribution(IERC20 token, uint256 totalAmount, uint256 weeksCount);
    event MovePastRewards(IERC20 token, uint256 moveAmount, uint256 pastWeekStart, uint256 nextWeekStart);
    event WeeksDistributions(IERC20 token, uint256 totalAmount, uint256 weeksCount);

    function depositEqualWeeksPeriod(IERC20 token, uint256 amount, uint256 weeksCount) external;
    function depositExactWeek(IERC20 token, uint256 amount, uint256 weekTimeStamp) external;
    function distributePastRewards(IERC20 token) external;
    function getTokenWeekAmounts(IERC20 token, uint256 pointOfWeek) external view returns (uint256);
    function getUpcomingRewardsForNWeeks(IERC20 token, uint256 weeksCount) external view returns (uint256[] memory);
    function initialize(address _rewardDistributor) external;
    function isInitialized() external view returns (bool);
    function movePastRewards(IERC20 token, uint256 pastWeekTimestamp) external;
    function rewardDistributor() external view returns (address);
    function tokenWeekAmounts(IERC20 token, uint256 weekStart) external view returns (uint256 amount);
    function totalTokenRewards(IERC20 token) external view returns (uint256 rewardAmount);

}

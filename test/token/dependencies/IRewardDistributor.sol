// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRewardDistributor {

    event NewAdmin(address indexed newAdmin);
    event OnlyCallerOptIn(address user, bool enabled);
    event RewardDeposit(IERC20 token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenCheckpointed(IERC20 token, uint256 amount, uint256 lastCheckpointTimestamp);
    event TokensClaimed(address user, IERC20 token, uint256 amount, uint256 userTokenTimeCursor);

    function addAllowedRewardTokens(IERC20[] memory tokens) external;
    function admin() external view returns (address);
    function allowedRewardTokens(IERC20) external view returns (bool);
    function checkpoint() external;
    function checkpointToken(IERC20 token) external;
    function checkpointTokens(IERC20[] memory tokens) external;
    function checkpointUser(address user) external;
    function claimToken(address user, IERC20 token) external returns (uint256);
    function claimTokens(address user, IERC20[] memory tokens) external returns (uint256[] memory);
    function depositToken(IERC20 token, uint256 amount) external;
    function depositTokens(address[] memory tokens, uint256[] memory amounts) external;
    function faucetDepositToken(IERC20 token, uint256 amount) external;
    function getAllowedRewardTokens() external view returns (IERC20[] memory);
    function getDomainSeparator() external view returns (bytes32);
    function getNextNonce(address account) external view returns (uint256);
    function getTimeCursor() external view returns (uint256);
    function getTokenLastBalance(IERC20 token) external view returns (uint256);
    function getTokenTimeCursor(IERC20 token) external view returns (uint256);
    function getTokensDistributedInWeek(IERC20 token, uint256 timestamp) external view returns (uint256);
    function getTotalSupplyAtTimestamp(uint256 timestamp) external view returns (uint256);
    function getUserBalanceAtTimestamp(address user, uint256 timestamp) external view returns (uint256);
    function getUserTimeCursor(address user) external view returns (uint256);
    function getUserTokenTimeCursor(address user, IERC20 token) external view returns (uint256);
    function getVotingEscrow() external view returns (address);
    function initialize(address votingEscrow, address rewardFaucet_, uint256 startTime, address admin_) external;
    function isInitialized() external view returns (bool);
    function isOnlyCallerEnabled(address user) external view returns (bool);
    function rewardFaucet() external view returns (address);
    function setOnlyCallerCheck(bool enabled) external;
    function setOnlyCallerCheckWithSignature(address user, bool enabled, bytes memory signature) external;
    function transferAdmin(address newAdmin) external;

}

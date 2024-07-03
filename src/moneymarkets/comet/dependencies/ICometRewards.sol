// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./IComet.sol";

interface ICometRewards {

    struct RewardConfig {
        IERC20 token;
        uint64 rescaleFactor;
        bool shouldUpscale;
    }

    struct RewardOwed {
        IERC20 token;
        uint256 owed;
    }

    error AlreadyConfigured(address);
    error BadData();
    error InvalidUInt64(uint256);
    error NotPermitted(address);
    error NotSupported(address);
    error TransferOutFailed(address, uint256);

    function claim(IComet comet, address from, bool shouldAccrue) external;
    function claimTo(IComet comet, address from, address to, bool shouldAccrue) external;
    function getRewardOwed(IComet comet, address account) external returns (RewardOwed memory);
    function governor() external view returns (address);
    function rewardConfig(IComet) external view returns (RewardConfig memory);
    function rewardsClaimed(IComet, address) external view returns (uint256);

}

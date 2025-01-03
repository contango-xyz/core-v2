// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUrdFactory {

    /// @notice Emitted when a new URD is created.
    /// @param urd The address of the newly created URD.
    /// @param caller The address of the caller.
    /// @param initialOwner The address of the URD owner.
    /// @param initialTimelock The URD timelock.
    /// @param initialRoot The URD's initial merkle root.
    /// @param initialIpfsHash The URD's initial ipfs hash.
    /// @param salt The salt used for CREATE2 opcode.
    event UrdCreated(
        address indexed urd,
        address indexed caller,
        address indexed initialOwner,
        uint256 initialTimelock,
        bytes32 initialRoot,
        bytes32 initialIpfsHash,
        bytes32 salt
    );

}

interface IUniversalRewardsDistributor {

    /// @notice Emitted when rewards are claimed.
    /// @param account The address for which rewards are claimed.
    /// @param reward The address of the reward token.
    /// @param amount The amount of reward token claimed.
    /// @param root The merkle root used to claim the reward.
    event Claimed(address indexed account, address indexed reward, uint256 amount, bytes32 indexed root);

}

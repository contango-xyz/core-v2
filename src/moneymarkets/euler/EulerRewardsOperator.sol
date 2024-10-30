/* solhint-disable avoid-low-level-calls */

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { OPERATOR_ROLE } from "../../libraries/Roles.sol";
import { Timelock, PositionId } from "../../libraries/DataTypes.sol";
import "../../libraries/ERC20Lib.sol";
import { Unauthorised } from "../../libraries/Errors.sol";
import "../../core/PositionNFT.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";

import "./dependencies/IEulerVault.sol";
import "./dependencies/IEthereumVaultConnector.sol";
import "./dependencies/IRewardStreams.sol";

import "./EulerReverseLookup.sol";

contract EulerRewardsOperator is AccessControl {

    using EnumerableSet for EnumerableSet.AddressSet;
    using ERC20Lib for *;

    event LiveRewardAdded(IERC20 reward);
    event LiveRewardRemoved(IERC20 reward);
    event RewardEnabled(PositionId positionId, IERC20 reward);
    event RewardDisabled(PositionId positionId, IERC20 reward);
    event RewardClaimed(PositionId positionId, IERC20 reward, address to, uint256 amount);

    error TooManyRewards();
    error InvalidReward();

    type AuthorisedProxy is address;

    bytes32 private constant DELEGATE_ROLE = keccak256("DELEGATE");

    PositionNFT public immutable positionNFT;
    IUnderlyingPositionFactory public immutable positionFactory;
    IEthereumVaultConnector public immutable evc;
    EulerReverseLookup public immutable reverseLookup;
    IRewardStreams public immutable rewardStreams;

    mapping(IEulerVault vault => EnumerableSet.AddressSet rewards) private _liveRewards;

    constructor(
        Timelock timelock,
        PositionNFT _positionNFT,
        IUnderlyingPositionFactory _positionFactory,
        IEthereumVaultConnector _evc,
        IRewardStreams _rewards,
        EulerReverseLookup _reverseLookup
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _grantRole(OPERATOR_ROLE, Timelock.unwrap(timelock));
        _grantRole(DELEGATE_ROLE, Timelock.unwrap(timelock));

        positionNFT = _positionNFT;
        positionFactory = _positionFactory;
        evc = _evc;
        rewardStreams = _rewards;
        reverseLookup = _reverseLookup;
    }

    function addLiveReward(IEulerVault vault, IERC20 reward) external onlyRole(OPERATOR_ROLE) {
        // RewardsStream accepts up to MAX_REWARDS_ENABLED rewards
        require(_liveRewards[vault].length() < rewardStreams.MAX_REWARDS_ENABLED(), TooManyRewards());
        if (_liveRewards[vault].add(address(reward))) emit LiveRewardAdded(reward);
    }

    function removeLiveReward(IEulerVault vault, IERC20 reward) external onlyRole(OPERATOR_ROLE) {
        if (_liveRewards[vault].remove(address(reward))) emit LiveRewardRemoved(reward);
    }

    function liveRewards(IEulerVault vault) external view returns (address[] memory) {
        return _liveRewards[vault].values();
    }

    function enableLiveRewards(PositionId positionId) external {
        IEulerVault vault = reverseLookup.base(positionId);
        AuthorisedProxy proxy = _authorise(positionId, true);
        EnumerableSet.AddressSet storage rewards = _liveRewards[vault];

        uint256 length = rewards.length();
        for (uint256 i; i < length;) {
            _enableReward(positionId, proxy, vault, IERC20(rewards.at(i)));
            unchecked {
                ++i;
            }
        }
    }

    function enableReward(PositionId positionId, IERC20 reward) external {
        _enableReward(positionId, _authorise(positionId, true), reverseLookup.base(positionId), reward);
    }

    function disableReward(PositionId positionId, IERC20 reward) external {
        IEulerVault vault = reverseLookup.base(positionId);
        AuthorisedProxy proxy = _authorise(positionId, true);

        // Make sure we claim pending rewards (if any) before disabling
        _claimReward(positionId, proxy, vault, reward, positionNFT.positionOwner(positionId));

        if (_callRewardsStreamBool(proxy, abi.encodeWithSelector(IRewardStreams.disableReward.selector, vault, reward, true))) {
            emit RewardDisabled(positionId, reward);
        }
    }

    function claimReward(PositionId positionId, IERC20 reward, address to) external {
        _claimReward(positionId, _authorise(positionId, false), reverseLookup.base(positionId), reward, to);
    }

    function claimAllRewards(PositionId positionId, address to) external {
        IEulerVault vault = reverseLookup.base(positionId);
        AuthorisedProxy proxy = _authorise(positionId, false);
        address[] memory rewards = rewardStreams.enabledRewards(AuthorisedProxy.unwrap(proxy), vault);
        uint256 length = rewards.length;
        for (uint256 i; i < length;) {
            _claimReward(positionId, proxy, vault, IERC20(rewards[i]), to);
            unchecked {
                ++i;
            }
        }
    }

    function _authorise(PositionId positionId, bool allowDelegate) internal view returns (AuthorisedProxy) {
        address msgSender = msg.sender;
        address proxy = address(positionFactory.moneyMarket(positionId));

        // Lazy evaluation of position owner
        require(
            proxy == msgSender || positionNFT.positionOwner(positionId) == msgSender || (allowDelegate && hasRole(DELEGATE_ROLE, msgSender)),
            Unauthorised(msgSender)
        );

        return AuthorisedProxy.wrap(proxy);
    }

    function _enableReward(PositionId positionId, AuthorisedProxy proxy, IEulerVault vault, IERC20 reward) internal {
        if (_callRewardsStreamBool(proxy, abi.encodeWithSelector(IRewardStreams.enableReward.selector, vault, reward))) {
            emit RewardEnabled(positionId, reward);
        }
    }

    function _claimReward(PositionId positionId, AuthorisedProxy proxy, IEulerVault vault, IERC20 reward, address to) internal {
        uint256 amount =
            _callRewardsStreamUint(proxy, abi.encodeWithSelector(IRewardStreams.claimReward.selector, vault, reward, to, false));
        if (amount > 0) emit RewardClaimed(positionId, reward, to, amount);
    }

    function _callRewardsStreamUint(AuthorisedProxy proxy, bytes memory data) internal returns (uint256) {
        return abi.decode(_callRewardsStream(proxy, data), (uint256));
    }

    function _callRewardsStreamBool(AuthorisedProxy proxy, bytes memory data) internal returns (bool) {
        return abi.decode(_callRewardsStream(proxy, data), (bool));
    }

    function _callRewardsStream(AuthorisedProxy proxy, bytes memory data) internal returns (bytes memory) {
        return evc.call(address(rewardStreams), AuthorisedProxy.unwrap(proxy), 0, data);
    }

}

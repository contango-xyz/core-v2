//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "../interfaces/IReferralManager.sol";
import "../libraries/Roles.sol";

contract ReferralManager is IReferralManager, AccessControl {

    uint256 public referrerRewardPercentage; // percentage in 1e4. e.g. 0.5e4 -> 5000 -> 50%
    uint256 public traderRebatePercentage; // percentage in 1e4. e.g. 0.5e4 -> 5000 -> 50%

    mapping(bytes32 code => address referrer) public referralCodes;
    mapping(address trader => address referrer) public referrals;

    constructor(Timelock timelock) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function setRewardsAndRebates(uint256 referrerReward, uint256 traderRebate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (referrerReward + traderRebate > ONE_HUNDRED_PERCENT) revert RewardsConfigCannotExceedMax();

        referrerRewardPercentage = referrerReward;
        traderRebatePercentage = traderRebate;

        emit RewardsAndRebatesSet(referrerReward, traderRebate);
    }

    function isCodeAvailable(bytes32 code) external view returns (bool) {
        return referralCodes[code] == address(0);
    }

    function registerReferralCode(bytes32 code) external {
        if (referralCodes[code] != address(0)) revert ReferralCodeUnavailable(code);
        referralCodes[code] = msg.sender;
        emit ReferralCodeRegistered(msg.sender, code);
    }

    function setTraderReferralByCode(bytes32 code) external {
        _setTraderReferralByCode(code, msg.sender);
    }

    function setTraderReferralByCodeForAddress(bytes32 code, address trader) external onlyRole(MODIFIER_ROLE) {
        _setTraderReferralByCode(code, trader);
    }

    function _setTraderReferralByCode(bytes32 code, address trader) internal {
        address referrer = referralCodes[code];
        if (referrer == address(0)) revert ReferralCodeNotRegistered(code);
        if (referrals[trader] != address(0)) revert ReferralCodeAlreadySet(code);
        if (trader == referrer) revert CannotSelfRefer();
        referrals[trader] = referrer;
        emit TraderReferred(trader, referrer, code);
    }

    function calculateRewardDistribution(address trader, uint256 amount) external view returns (FeeDistribution memory feeDistribution) {
        feeDistribution.protocol = amount;
        feeDistribution.referrerAddress = referrals[trader];

        if (feeDistribution.referrerAddress != address(0)) {
            feeDistribution.referrer = (amount * referrerRewardPercentage) / ONE_HUNDRED_PERCENT;
            feeDistribution.trader = (amount * traderRebatePercentage) / ONE_HUNDRED_PERCENT;
            feeDistribution.protocol = amount - feeDistribution.referrer - feeDistribution.trader;
        }
    }

}

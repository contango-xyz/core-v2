//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IContango.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/IReferralManager.sol";
import "../interfaces/IVault.sol";

import "../libraries/Roles.sol";
import "../libraries/ERC20Lib.sol";

contract FeeManager is IFeeManager, AccessControlUpgradeable, UUPSUpgradeable {

    using ERC20Lib for *;

    address public immutable treasury;
    IVault public immutable vault;
    IFeeModel public immutable feeModel;
    IReferralManager public immutable referralManager;

    constructor(address _treasury, IVault _vault, IFeeModel _feeModel, IReferralManager _referralManager) {
        treasury = _treasury;
        vault = _vault;
        feeModel = _feeModel;
        referralManager = _referralManager;
    }

    function initialize(Timelock timelock) public initializer {
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function applyFee(address trader, PositionId positionId, uint256 quantity)
        external
        override
        onlyRole(CONTANGO_ROLE)
        returns (uint256 fee, Currency feeCcy)
    {
        fee = feeModel.calculateFee(trader, positionId, quantity);
        feeCcy = Currency.Base;

        uint256 protocolFee = fee;
        if (fee > 0) {
            // msg.sender must be contango
            IERC20 base = IContango(msg.sender).instrument(positionId.getSymbol()).base;
            base.transferOut(msg.sender, address(vault), fee);

            FeeDistribution memory feeDistribution = referralManager.calculateRewardDistribution(trader, fee);

            if (feeDistribution.referrerAddress != address(0)) {
                if (feeDistribution.referrer > 0) vault.depositTo(base, feeDistribution.referrerAddress, feeDistribution.referrer);

                if (feeDistribution.trader > 0) vault.depositTo(base, trader, feeDistribution.trader);

                protocolFee = feeDistribution.protocol;
            }
            vault.depositTo(base, treasury, protocolFee);

            emit FeePaid({
                positionId: positionId,
                trader: trader,
                referrer: feeDistribution.referrerAddress,
                referrerAmount: feeDistribution.referrer,
                traderRebate: feeDistribution.trader,
                protocolFee: protocolFee,
                feeCcy: feeCcy
            });
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}

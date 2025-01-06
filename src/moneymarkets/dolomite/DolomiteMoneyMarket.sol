//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IDolomiteMargin.sol";
import "./dependencies/IIsolationToken.sol";

import "../BaseMoneyMarket.sol";
import "../../libraries/ERC20Lib.sol";
import { MM_DOLOMITE } from "script/constants.sol";

contract DolomiteMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;

    IDolomiteMargin public immutable dolomite;
    IIsolationVault public vault;

    constructor(IContango _contango, IDolomiteMargin _dolomite) BaseMoneyMarket(MM_DOLOMITE, _contango) {
        dolomite = _dolomite;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        address approveCollateralTo = address(dolomite);

        uint256 isolatedMarketId = uint40(Payload.unwrap(positionId.getPayload()));
        if (isolatedMarketId > 0) {
            vault = IIsolationToken(address(dolomite.getMarketTokenAddress(isolatedMarketId))).createVault(address(this));
            approveCollateralTo = address(vault);
        }

        SafeERC20.forceApprove(collateralAsset, approveCollateralTo, type(uint256).max);
        SafeERC20.forceApprove(debtAsset, address(dolomite), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view override returns (uint256 balance) {
        return _isIsolationMode()
            ? vault.underlyingBalanceOf()
            : dolomite.getAccountWei(_self(), dolomite.getMarketIdByTokenAddress(asset)).value;
    }

    function _debtBalance(PositionId positionId, IERC20 asset) internal view override returns (uint256 balance) {
        IDolomiteMargin.Info memory self = _isIsolationMode() ? IDolomiteMargin.Info(address(vault), _accountNumber(positionId)) : _self();
        return dolomite.getAccountWei(self, dolomite.getMarketIdByTokenAddress(asset)).value;
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        actualAmount = asset.transferOut(payer, address(this), amount);
        if (_isIsolationMode()) {
            vault.depositIntoVaultForDolomiteMargin(0, actualAmount);
            vault.openBorrowPosition(0, _accountNumber(positionId), actualAmount);
        } else {
            __deposit(asset, actualAmount);
        }
    }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        if (_isIsolationMode()) vault.transferFromPositionWithOtherToken(_accountNumber(positionId), 0, 0, amount, BalanceCheck.None);
        __withdraw(asset, actualAmount = amount, to);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, debt);
        if (actualAmount > 0) {
            __deposit(asset, asset.transferOut(payer, address(this), actualAmount));
            if (_isIsolationMode()) {
                vault.transferIntoPositionWithOtherToken(0, _accountNumber(positionId), 0, actualAmount, BalanceCheck.None);
            }
        }
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        if (_isIsolationMode()) {
            vault.transferFromPositionWithUnderlyingToken(_accountNumber(positionId), 0, amount);
            vault.withdrawFromVaultForDolomiteMargin(0, amount);
            actualAmount = asset.transferOut(address(this), to, amount);
        } else {
            __withdraw(asset, actualAmount = amount, to);
        }
    }

    function _accountNumber(PositionId positionId) internal view returns (uint256) {
        // Hack to deal with old positions created before the account number change
        return positionId.getNumber() > 4863 ? positionId.asUint() : uint160(address(this));
    }

    function _self() internal view returns (IDolomiteMargin.Info memory self) {
        self.owner = address(this);
    }

    function _accounts() internal view returns (IDolomiteMargin.Info[] memory accounts) {
        accounts = new IDolomiteMargin.Info[](1);
        accounts[0] = _self();
    }

    function _actions(IERC20 asset) internal view returns (IDolomiteMargin.ActionArgs[] memory actions) {
        actions = new IDolomiteMargin.ActionArgs[](1);
        actions[0].primaryMarketId = dolomite.getMarketIdByTokenAddress(asset);
    }

    function __deposit(IERC20 asset, uint256 amount) internal {
        IDolomiteMargin.ActionArgs[] memory actions = _actions(asset);
        actions[0].actionType = IDolomiteMargin.ActionType.Deposit;
        actions[0].amount.sign = true;
        actions[0].amount.value = amount;
        actions[0].otherAddress = address(this);

        dolomite.operate(_accounts(), actions);
    }

    function __withdraw(IERC20 asset, uint256 amount, address to) internal {
        IDolomiteMargin.ActionArgs[] memory actions = _actions(asset);
        actions[0].actionType = IDolomiteMargin.ActionType.Withdraw;
        actions[0].amount.value = amount;
        actions[0].otherAddress = to;

        dolomite.operate(_accounts(), actions);
    }

    function _isIsolationMode() internal view returns (bool) {
        return vault != IIsolationVault(address(0));
    }

}

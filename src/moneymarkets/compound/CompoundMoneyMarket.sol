//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";

import "../BaseMoneyMarket.sol";

import "./dependencies/IComptroller.sol";
import "./CompoundReverseLookup.sol";

contract CompoundMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for IERC20;
    using SafeERC20 for IERC20;

    error FailedToBorrow(Error _error);
    error FailedToRepay(Error _error);
    error FailedToRedeem(Error _error);
    error FailedToLend(Error _error);
    error FailedToEnterMarket(Error _error);

    bool public constant override NEEDS_ACCOUNT = true;

    CompoundReverseLookup public immutable reverseLookup;
    IComptroller public immutable comptroller;
    IWETH9 public immutable nativeToken;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, CompoundReverseLookup _reverseLookup, IWETH9 _nativeToken)
        BaseMoneyMarket(_moneyMarketId, _contango)
    {
        reverseLookup = _reverseLookup;
        comptroller = _reverseLookup.comptroller();
        nativeToken = _nativeToken;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();
        if (collateralAsset != nativeToken) collateralAsset.forceApprove(address(cToken(collateralAsset)), type(uint256).max);
        if (debtAsset != nativeToken) debtAsset.forceApprove(address(cToken(debtAsset)), type(uint256).max);
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer, uint256) internal override returns (uint256 actualAmount) {
        asset.transferOut(payer, address(this), amount);

        Error _error;
        ICToken _cToken = cToken(asset);
        if (asset == nativeToken) {
            nativeToken.withdraw(amount);
            _cToken.mint{ value: amount }();
        } else {
            _error = _cToken.mint(amount);
            if (_error != Error.NO_ERROR) revert FailedToLend(_error);
        }
        actualAmount = amount;

        _error = comptroller.enterMarkets(toArray(address(_cToken)))[0];
        if (_error != Error.NO_ERROR) revert FailedToEnterMarket(_error);
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to, uint256) internal override returns (uint256 actualAmount) {
        ICToken _cToken = cToken(asset);
        actualAmount = Math.min(amount, _cToken.balanceOfUnderlying(address(this)));
        Error _error = _cToken.redeemUnderlying(actualAmount);
        if (_error != Error.NO_ERROR) revert FailedToRedeem(_error);

        if (asset == nativeToken) nativeToken.deposit{ value: actualAmount }();
        asset.transferOut(address(this), to, actualAmount);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to, uint256) internal override returns (uint256 actualAmount) {
        Error _error = cToken(asset).borrow(amount);
        if (_error != Error.NO_ERROR) revert FailedToBorrow(_error);

        if (asset == nativeToken) nativeToken.deposit{ value: amount }();
        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        override
        returns (uint256 actualAmount)
    {
        ICToken _cToken = cToken(asset);
        actualAmount = Math.min(amount, debt);
        asset.transferOut(payer, address(this), actualAmount);

        if (asset == nativeToken) {
            nativeToken.withdraw(actualAmount);
            _cToken.repayBorrow{ value: actualAmount }();
        } else {
            Error _error = _cToken.repayBorrow(actualAmount);
            if (_error != Error.NO_ERROR) revert FailedToRepay(_error);
        }
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        comptroller.claimComp({
            holders: toArray(address(this)),
            cTokens: toArray(address(cToken(collateralAsset))),
            borrowers: false,
            suppliers: true
        });
        comptroller.claimComp({
            holders: toArray(address(this)),
            cTokens: toArray(address(cToken(debtAsset))),
            borrowers: true,
            suppliers: false
        });
        IERC20(comptroller.getCompAddress()).transferBalance(to);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal override returns (uint256 balance) {
        balance = cToken(asset).balanceOfUnderlying(address(this));
    }

    function _debtBalance(PositionId, IERC20 asset) internal override returns (uint256 balance) {
        balance = cToken(asset).borrowBalanceCurrent(address(this));
    }

    function cToken(IERC20 asset) public view returns (ICToken) {
        return reverseLookup.cToken(asset);
    }

    receive() external payable virtual {
        // allow native token
    }

}

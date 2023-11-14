//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";

import "../BaseMoneyMarket.sol";

import "./dependencies/IComptroller.sol";

contract SonneMoneyMarket is BaseMoneyMarket {

    using ERC20Lib for IERC20;
    using SafeERC20 for IERC20;

    error FailedToBorrow(Error _error);
    error FailedToRepay(Error _error);
    error FailedToRedeem(Error _error);
    error FailedToLend(Error _error);
    error FailedToEnterMarket(Error _error);
    error UnsupportedAsset(IERC20 asset);

    bool public constant override NEEDS_ACCOUNT = true;

    IComptroller public immutable comptroller;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango, IComptroller _comptroller) BaseMoneyMarket(_moneyMarketId, _contango) {
        comptroller = _comptroller;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();
        collateralAsset.forceApprove(address(cToken(collateralAsset)), type(uint256).max);
        debtAsset.forceApprove(address(cToken(debtAsset)), type(uint256).max);
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        asset.transferOut(payer, address(this), amount);

        ICToken _cToken = cToken(asset);
        Error _error = _cToken.mint(amount);
        if (_error != Error.NO_ERROR) revert FailedToLend(_error);
        actualAmount = amount;

        _error = comptroller.enterMarkets(toArray(address(_cToken)))[0];
        if (_error != Error.NO_ERROR) revert FailedToEnterMarket(_error);
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        ICToken _cToken = cToken(asset);
        actualAmount = Math.min(amount, _cToken.balanceOfUnderlying(address(this)));
        Error _error = _cToken.redeemUnderlying(actualAmount);
        if (_error != Error.NO_ERROR) revert FailedToRedeem(_error);

        asset.transferOut(address(this), to, actualAmount);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        Error _error = cToken(asset).borrow(amount);
        if (_error != Error.NO_ERROR) revert FailedToBorrow(_error);

        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        ICToken _cToken = cToken(asset);
        actualAmount = Math.min(amount, _cToken.borrowBalanceCurrent(address(this)));
        asset.transferOut(payer, address(this), actualAmount);

        Error _error = _cToken.repayBorrow(actualAmount);
        if (_error != Error.NO_ERROR) revert FailedToRepay(_error);
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal override {
        comptroller.claimComp(address(this), toArray(address(cToken(collateralAsset)), address(cToken(debtAsset))));
        IERC20(comptroller.getCompAddress()).transferBalance(to);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal override returns (uint256 balance) {
        balance = cToken(asset).balanceOfUnderlying(address(this));
    }

    function cToken(IERC20 asset) public view returns (ICToken cToken_) {
        address[] memory allMarkets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < allMarkets.length; i++) {
            cToken_ = ICToken(allMarkets[i]);
            if (cToken_.underlying() == address(asset)) return cToken_;
        }
        revert UnsupportedAsset(asset);
    }

}

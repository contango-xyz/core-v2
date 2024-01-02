//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../interfaces/IContango.sol";
import "../libraries/Errors.sol";

import "./interfaces/IMoneyMarket.sol";

abstract contract BaseMoneyMarket is IMoneyMarket {

    MoneyMarketId public immutable moneyMarketId;
    IContango public immutable contango;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango) {
        moneyMarketId = _moneyMarketId;
        contango = _contango;
    }

    function initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external override onlyContango {
        if (MoneyMarketId.unwrap(positionId.getMoneyMarket()) != MoneyMarketId.unwrap(moneyMarketId)) revert InvalidMoneyMarketId();
        _initialise(positionId, collateralAsset, debtAsset);
    }

    function lend(PositionId positionId, IERC20 asset, uint256 amount) external override onlyContango returns (uint256) {
        if (amount == 0) return 0;
        return _lend(positionId, asset, amount, msg.sender);
    }

    function withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) external override onlyContango returns (uint256) {
        if (amount == 0) return 0;
        return _withdraw(positionId, asset, amount, to);
    }

    function borrow(PositionId positionId, IERC20 asset, uint256 amount, address to) external override onlyContango returns (uint256) {
        if (amount == 0) return 0;
        return _borrow(positionId, asset, amount, to);
    }

    function repay(PositionId positionId, IERC20 asset, uint256 amount) external override onlyContango returns (uint256) {
        if (amount == 0) return 0;
        return _repay(positionId, asset, amount, msg.sender);
    }

    function claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) external override onlyContango {
        _claimRewards(positionId, collateralAsset, debtAsset, to);
    }

    function collateralBalance(PositionId positionId, IERC20 asset) external override returns (uint256) {
        return _collateralBalance(positionId, asset);
    }

    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual;

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal virtual returns (uint256 actualAmount);

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) internal virtual returns (uint256 actualAmount);

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to) internal virtual returns (uint256 actualAmount);

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal virtual returns (uint256 actualAmount);

    function _claimRewards(PositionId, IERC20, IERC20, address) internal virtual {
        revert RewardsNotImplemented();
    }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal virtual returns (uint256 balance);

    modifier onlyContango() {
        if (msg.sender != address(contango)) revert Unauthorised(msg.sender);
        _;
    }

}

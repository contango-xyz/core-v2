//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IContangoOracle.sol";
import "./interfaces/IMoneyMarketView.sol";

contract ContangoLens is AccessControlUpgradeable, UUPSUpgradeable, IContangoOracle {

    event MoneyMarketViewRegistered(MoneyMarketId indexed mm, IMoneyMarketView indexed moneyMarketView);

    error InvalidMoneyMarket(MoneyMarketId mm);

    mapping(MoneyMarketId mmId => IMoneyMarketView mmv) public moneyMarketViews;

    function initialize(Timelock timelock) public initializer {
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function setMoneyMarketView(IMoneyMarketView immv) external onlyRole(DEFAULT_ADMIN_ROLE) {
        MoneyMarketId mm = immv.moneyMarketId();
        moneyMarketViews[mm] = immv;
        emit MoneyMarketViewRegistered(mm, immv);
    }

    function moneyMarketId(PositionId positionId) external view returns (MoneyMarketId) {
        return moneyMarketView(positionId).moneyMarketId();
    }

    function moneyMarketId(MoneyMarketId mmId) external view returns (MoneyMarketId) {
        return moneyMarketView(mmId).moneyMarketId();
    }

    function moneyMarketName(PositionId positionId) external view returns (string memory) {
        return moneyMarketView(positionId).moneyMarketName();
    }

    function moneyMarketName(MoneyMarketId mmId) external view returns (string memory) {
        return moneyMarketView(mmId).moneyMarketName();
    }

    function balances(PositionId positionId) external returns (Balances memory balances_) {
        return moneyMarketView(positionId).balances(positionId);
    }

    function prices(PositionId positionId) external view returns (Prices memory prices_) {
        return moneyMarketView(positionId).prices(positionId);
    }

    function priceInNativeToken(PositionId positionId, IERC20 asset) external view returns (uint256 price_) {
        return moneyMarketView(positionId).priceInNativeToken(asset);
    }

    function priceInNativeToken(MoneyMarketId mmId, IERC20 asset) external view returns (uint256 price_) {
        return moneyMarketView(mmId).priceInNativeToken(asset);
    }

    function priceInUSD(PositionId positionId, IERC20 asset) external view returns (uint256 price_) {
        return moneyMarketView(positionId).priceInUSD(asset);
    }

    function priceInUSD(MoneyMarketId mmId, IERC20 asset) external view returns (uint256 price_) {
        return moneyMarketView(mmId).priceInUSD(asset);
    }

    function baseQuoteRate(PositionId positionId) external view returns (uint256) {
        return moneyMarketView(positionId).baseQuoteRate(positionId);
    }

    function thresholds(PositionId positionId) external view returns (uint256 ltv, uint256 liquidationThreshold) {
        return moneyMarketView(positionId).thresholds(positionId);
    }

    function liquidity(PositionId positionId) external view returns (uint256 borrowing, uint256 lending) {
        return moneyMarketView(positionId).liquidity(positionId);
    }

    function rates(PositionId positionId) external view returns (uint256 borrowing, uint256 lending) {
        return moneyMarketView(positionId).rates(positionId);
    }

    function rewards(PositionId positionId) external returns (Reward[] memory borrowing, Reward[] memory lending) {
        return moneyMarketView(positionId).rewards(positionId);
    }

    function moneyMarketView(PositionId positionId) public view returns (IMoneyMarketView moneyMarketView_) {
        return moneyMarketView(positionId.getMoneyMarket());
    }

    function moneyMarketView(MoneyMarketId mmId) public view returns (IMoneyMarketView moneyMarketView_) {
        moneyMarketView_ = moneyMarketViews[mmId];
        if (address(moneyMarketView_) == address(0)) revert InvalidMoneyMarket(mmId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "src/moneymarkets/interfaces/IMoneyMarketView.sol";

contract StubMoneyMarketView is IMoneyMarketView {

    struct FeatureToggle {
        bool rewards;
    }

    IMoneyMarketView public immutable delegate;
    FeatureToggle public featureToggle;

    constructor(IMoneyMarketView delegate_, FeatureToggle memory featureToggle_) {
        delegate = delegate_;
        featureToggle = featureToggle_;
    }

    function moneyMarketId() external view returns (MoneyMarketId) {
        return delegate.moneyMarketId();
    }

    function moneyMarketName() external view returns (string memory) {
        return delegate.moneyMarketName();
    }

    function balances(PositionId positionId) external returns (Balances memory balances_) {
        return delegate.balances(positionId);
    }

    function balancesUSD(PositionId positionId) external returns (Balances memory balances_) {
        return delegate.balancesUSD(positionId);
    }

    function prices(PositionId positionId) external view returns (Prices memory prices_) {
        return delegate.prices(positionId);
    }

    function baseQuoteRate(PositionId positionId) external view returns (uint256) {
        return delegate.baseQuoteRate(positionId);
    }

    function priceInNativeToken(IERC20 asset) external view returns (uint256 price_) {
        return delegate.priceInNativeToken(asset);
    }

    function priceInUSD(IERC20 asset) external view returns (uint256 price_) {
        return delegate.priceInUSD(asset);
    }

    function thresholds(PositionId positionId) external view returns (uint256 ltv, uint256 liquidationThreshold) {
        return delegate.thresholds(positionId);
    }

    function liquidity(PositionId positionId) external view returns (uint256 borrowing, uint256 lending) {
        return delegate.liquidity(positionId);
    }

    function rates(PositionId positionId) external view returns (uint256 borrowing, uint256 lending) {
        return delegate.rates(positionId);
    }

    function irmRaw(PositionId positionId) external returns (bytes memory data) {
        return delegate.irmRaw(positionId);
    }

    function rewards(PositionId positionId) external returns (Reward[] memory borrowing, Reward[] memory lending) {
        if (featureToggle.rewards) return delegate.rewards(positionId);
    }

    function availableActions(PositionId positionId) external returns (AvailableActions[] memory available) {
        return delegate.availableActions(positionId);
    }

    function limits(PositionId positionId) external view returns (Limits memory limits_) {
        return delegate.limits(positionId);
    }

}

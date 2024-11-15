// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./IMoneyMarketView.sol";
import "../ContangoLens.sol";

// Hack to make all functions view on the ABI
interface IContangoLens {

    error CallFailed(address target, bytes4 selector);
    error InvalidMoneyMarket(MoneyMarketId mm);

    function moneyMarketViews(MoneyMarketId mmId) external view returns (IMoneyMarketView);
    function setMoneyMarketView(IMoneyMarketView immv) external;
    function availableActions(PositionId positionId) external view returns (AvailableActions[] memory available);
    function balances(PositionId positionId) external view returns (Balances memory balances_);
    function balancesUSD(PositionId positionId) external view returns (Balances memory balancesUSD_);
    function baseQuoteRate(PositionId positionId) external view returns (uint256);
    function irmRaw(PositionId positionId) external view returns (bytes memory data);
    function leverage(PositionId positionId) external view returns (uint256 leverage_);
    function limits(PositionId positionId) external view returns (Limits memory limits_);
    function liquidity(PositionId positionId) external view returns (uint256 borrowing, uint256 lending);
    function metaData(PositionId positionId) external view returns (ContangoLens.MetaData memory metaData_);
    function netRate(PositionId positionId) external view returns (int256 netRate_);
    function priceInNativeToken(PositionId positionId, address asset) external view returns (uint256 price_);
    function priceInNativeToken(MoneyMarketId mmId, address asset) external view returns (uint256 price_);
    function priceInUSD(MoneyMarketId mmId, address asset) external view returns (uint256 price_);
    function priceInUSD(PositionId positionId, address asset) external view returns (uint256 price_);
    function prices(PositionId positionId) external view returns (Prices memory prices_);
    function rates(PositionId positionId) external view returns (uint256 borrowing, uint256 lending);
    function rewards(PositionId positionId) external view returns (Reward[] memory borrowing, Reward[] memory lending);
    function thresholds(PositionId positionId) external view returns (uint256 ltv, uint256 liquidationThreshold);

}

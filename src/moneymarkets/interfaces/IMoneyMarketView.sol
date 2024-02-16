//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../../libraries/DataTypes.sol";

struct Balances {
    uint256 collateral;
    uint256 debt;
}

struct Prices {
    uint256 collateral;
    uint256 debt;
    uint256 unit;
}

struct TokenData {
    IERC20 token;
    string name;
    string symbol;
    uint8 decimals;
    uint256 unit;
}

struct Reward {
    TokenData token;
    uint256 rate;
    uint256 claimable;
    uint256 usdPrice;
}

interface IMoneyMarketView {

    error UnsupportedAsset(IERC20 asset);

    function moneyMarketId() external view returns (MoneyMarketId);

    function moneyMarketName() external view returns (string memory);

    function balances(PositionId positionId) external returns (Balances memory balances_);

    function prices(PositionId positionId) external view returns (Prices memory prices_);

    function baseQuoteRate(PositionId positionId) external view returns (uint256);

    function priceInNativeToken(IERC20 asset) external view returns (uint256 price_);

    function priceInUSD(IERC20 asset) external view returns (uint256 price_);

    function thresholds(PositionId positionId) external view returns (uint256 ltv, uint256 liquidationThreshold);

    function liquidity(PositionId positionId) external view returns (uint256 borrowing, uint256 lending);

    function rates(PositionId positionId) external view returns (uint256 borrowing, uint256 lending);

    function rewards(PositionId positionId) external returns (Reward[] memory borrowing, Reward[] memory lending);

}

function asTokenData(IERC20 token) view returns (TokenData memory tokenData_) {
    tokenData_.token = token;
    tokenData_.name = token.name();
    tokenData_.symbol = token.symbol();
    tokenData_.decimals = token.decimals();
    tokenData_.unit = 10 ** token.decimals();
}

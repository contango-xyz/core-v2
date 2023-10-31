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

interface IMoneyMarketView {

    function moneyMarketId() external view returns (MoneyMarketId);

    function balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external returns (Balances memory balances_);

    function prices(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external view returns (Prices memory prices_);

    function thresholds(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        external
        view
        returns (uint256 ltv, uint256 liquidationThreshold);

    function liquidity(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        external
        view
        returns (uint256 borrowing, uint256 lending);

    function rates(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        external
        view
        returns (uint256 borrowing, uint256 lending);

}

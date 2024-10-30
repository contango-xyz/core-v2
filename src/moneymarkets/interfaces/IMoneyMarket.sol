//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { PositionId, MoneyMarketId } from "../../libraries/DataTypes.sol";

interface IMoneyMarket is IERC165 {

    event Borrowed(PositionId indexed positionId, IERC20 indexed asset, uint256 amount);
    event Lent(PositionId indexed positionId, IERC20 indexed asset, uint256 amount);
    event Repaid(PositionId indexed positionId, IERC20 indexed asset, uint256 amount);
    event Withdrawn(PositionId indexed positionId, IERC20 indexed asset, uint256 amount);
    event RewardsClaimed(PositionId indexed positionId, address to);
    event RewardsClaimed(PositionId indexed positionId, IERC20 indexed rewardsToken, address to, uint256 rewardsAmount);
    event Retrieved(PositionId indexed positionId, IERC20 indexed token, uint256 amount);

    error InvalidMoneyMarketId();
    error InvalidPositionId(PositionId positionId);
    error TokenCantBeRetrieved(IERC20 token);

    /// @dev indicates whether the money market requires an underlying account to be created
    /// if true, the money market must be cloned to create an underlying position
    /// otherwise the money market can be used directly as it know how to isolate positions
    function NEEDS_ACCOUNT() external view returns (bool);

    function moneyMarketId() external view returns (MoneyMarketId);

    function initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external;

    function lend(PositionId positionId, IERC20 asset, uint256 amount) external returns (uint256 actualAmount);

    function withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) external returns (uint256 actualAmount);

    function borrow(PositionId positionId, IERC20 asset, uint256 amount, address to) external returns (uint256 actualAmount);

    function repay(PositionId positionId, IERC20 asset, uint256 amount) external returns (uint256 actualAmount);

    function claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) external;

    function collateralBalance(PositionId positionId, IERC20 asset) external returns (uint256 balance);

    function debtBalance(PositionId positionId, IERC20 asset) external returns (uint256 balance);

    function retrieve(PositionId positionId, IERC20 token) external returns (uint256 amount);

}

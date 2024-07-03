// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IPoolConfiguratorV2 {

    function activateReserve(IERC20 asset) external;
    function configureReserveAsCollateral(IERC20 asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus) external;
    function deactivateReserve(IERC20 asset) external;
    function disableBorrowingOnReserve(IERC20 asset) external;
    function disableReserveStableRate(IERC20 asset) external;
    function enableBorrowingOnReserve(IERC20 asset, bool stableBorrowRateEnabled) external;
    function enableReserveStableRate(IERC20 asset) external;
    function freezeReserve(IERC20 asset) external;
    function initReserve(
        address aTokenImpl,
        address stableDebtTokenImpl,
        address variableDebtTokenImpl,
        uint8 underlyingAssetDecimals,
        address interestRateStrategyAddress
    ) external;
    function initialize(address provider) external;
    function setPoolPause(bool val) external;
    function setReserveFactor(IERC20 asset, uint256 reserveFactor) external;
    function setReserveInterestRateStrategyAddress(IERC20 asset, address rateStrategyAddress) external;
    function unfreezeReserve(IERC20 asset) external;
    function updateAToken(IERC20 asset, address implementation) external;
    function updateStableDebtToken(IERC20 asset, address implementation) external;
    function updateVariableDebtToken(IERC20 asset, address implementation) external;

}

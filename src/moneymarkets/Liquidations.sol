// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

interface Liquidations {

    // ====================== Aave ======================

    // Aave V3
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken
    );

    function ADDRESSES_PROVIDER() external view returns (address);

    // Aave V2
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken,
        bool useAToken
    );

    // Radiant
    event LiquidationCall(
        address indexed collateral,
        address indexed principal,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken,
        address liquidationFeeTo
    );

    // Aave common
    struct ReserveConfigurationMap {
        uint256 data;
    }

    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);

    // ====================== Exactly ======================

    event Liquidate(
        address indexed receiver,
        address indexed borrower,
        uint256 assets,
        uint256 lendersAssets,
        address indexed seizeMarket,
        uint256 seizedAssets
    );

    // ====================== Compound ======================

    event LiquidateBorrow(address liquidator, address borrower, uint256 repayAmount, address cTokenCollateral, uint256 seizeTokens);

}

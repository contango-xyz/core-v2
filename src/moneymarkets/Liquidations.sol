// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./dolomite/dependencies/IDolomiteMargin.sol";

interface Liquidations {

    // ====================== Aave ======================

    // Aave V2/V3
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

    // Agave
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

    // ====================== Morpho Blue ======================

    event Liquidate(
        bytes32 indexed id,
        address indexed caller,
        address indexed borrower,
        uint256 repaidAssets,
        uint256 repaidShares,
        uint256 seizedAssets,
        uint256 badDebtAssets,
        uint256 badDebtShares
    );

    // ====================== Silo ======================

    event Liquidate(address indexed asset, address indexed user, uint256 shareAmountRepaid, uint256 seizedCollateral);

    // ====================== Comet ======================

    event AbsorbCollateral(
        address indexed absorber, address indexed borrower, address indexed asset, uint256 collateralAbsorbed, uint256 usdValue
    );
    event AbsorbDebt(address indexed absorber, address indexed borrower, uint256 basePaidOut, uint256 usdValue);

    // ====================== Dolomite ======================

    event LogLiquidate(
        address indexed solidAccountOwner,
        uint256 solidAccountNumber,
        address indexed liquidAccountOwner,
        uint256 liquidAccountNumber,
        uint256 heldMarket,
        uint256 owedMarket,
        IDolomiteMargin.BalanceUpdate solidHeldUpdate,
        IDolomiteMargin.BalanceUpdate solidOwedUpdate,
        IDolomiteMargin.BalanceUpdate liquidHeldUpdate,
        IDolomiteMargin.BalanceUpdate liquidOwedUpdate
    );

    // ====================== Euler ======================

    /// @notice Liquidate unhealthy account
    /// @param liquidator Address executing the liquidation
    /// @param violator Address holding an unhealthy borrow
    /// @param collateral Address of the asset seized
    /// @param repayAssets Amount of debt in assets transferred from violator to liquidator
    /// @param yieldBalance Amount of collateral asset's balance transferred from violator to liquidator
    event Liquidate(address indexed liquidator, address indexed violator, address collateral, uint256 repayAssets, uint256 yieldBalance);

}

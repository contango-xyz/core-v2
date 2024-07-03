// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IPoolConfigurator {

    struct InitReserveInput {
        address aTokenImpl;
        address stableDebtTokenImpl;
        address variableDebtTokenImpl;
        uint8 underlyingAssetDecimals;
        address interestRateStrategyAddress;
        address underlyingAsset;
        address treasury;
        address incentivesController;
        string aTokenName;
        string aTokenSymbol;
        string variableDebtTokenName;
        string variableDebtTokenSymbol;
        string stableDebtTokenName;
        string stableDebtTokenSymbol;
        bytes params;
    }

    struct UpdateATokenInput {
        IERC20 asset;
        address treasury;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    struct UpdateDebtTokenInput {
        IERC20 asset;
        address incentivesController;
        string name;
        string symbol;
        address implementation;
        bytes params;
    }

    function CONFIGURATOR_REVISION() external view returns (uint256);
    function configureReserveAsCollateral(IERC20 asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus) external;
    function dropReserve(IERC20 asset) external;
    function initReserves(InitReserveInput[] memory input) external;
    function initialize(address provider) external;
    function setAssetEModeCategory(IERC20 asset, uint8 newCategoryId) external;
    function setBorrowCap(IERC20 asset, uint256 newBorrowCap) external;
    function setBorrowableInIsolation(IERC20 asset, bool borrowable) external;
    function setDebtCeiling(IERC20 asset, uint256 newDebtCeiling) external;
    function setEModeCategory(
        uint8 categoryId,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        address oracle,
        string memory label
    ) external;
    function setLiquidationProtocolFee(IERC20 asset, uint256 newFee) external;
    function setPoolPause(bool paused) external;
    function setReserveActive(IERC20 asset, bool active) external;
    function setReserveBorrowing(IERC20 asset, bool enabled) external;
    function setReserveFactor(IERC20 asset, uint256 newReserveFactor) external;
    function setReserveFlashLoaning(IERC20 asset, bool enabled) external;
    function setReserveFreeze(IERC20 asset, bool freeze) external;
    function setReserveInterestRateStrategyAddress(IERC20 asset, address newRateStrategyAddress) external;
    function setReservePause(IERC20 asset, bool paused) external;
    function setReserveStableRateBorrowing(IERC20 asset, bool enabled) external;
    function setSiloedBorrowing(IERC20 asset, bool newSiloed) external;
    function setSupplyCap(IERC20 asset, uint256 newSupplyCap) external;
    function setUnbackedMintCap(IERC20 asset, uint256 newUnbackedMintCap) external;
    function updateAToken(UpdateATokenInput memory input) external;
    function updateBridgeProtocolFee(uint256 newBridgeProtocolFee) external;
    function updateFlashloanPremiumToProtocol(uint128 newFlashloanPremiumToProtocol) external;
    function updateFlashloanPremiumTotal(uint128 newFlashloanPremiumTotal) external;
    function updateStableDebtToken(UpdateDebtTokenInput memory input) external;
    function updateVariableDebtToken(UpdateDebtTokenInput memory input) external;

}

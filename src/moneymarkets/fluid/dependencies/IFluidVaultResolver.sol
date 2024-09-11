// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./IFluidVault.sol";
import "./IFluidLiquidityResolver.sol";

interface IFluidVaultResolver {

    struct ConstantViews {
        address liquidity;
        address factory;
        address adminImplementation;
        address secondaryImplementation;
        IERC20 supplyToken;
        IERC20 borrowToken;
        uint8 supplyDecimals;
        uint8 borrowDecimals;
        uint256 vaultId;
        bytes32 liquiditySupplyExchangePriceSlot;
        bytes32 liquidityBorrowExchangePriceSlot;
        bytes32 liquidityUserSupplySlot;
        bytes32 liquidityUserBorrowSlot;
    }

    struct AbsorbStruct {
        address vault;
        bool absorbAvailable;
    }

    struct Configs {
        uint16 supplyRateMagnifier;
        uint16 borrowRateMagnifier;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationMaxLimit;
        uint16 withdrawalGap;
        uint16 liquidationPenalty;
        uint16 borrowFee;
        address oracle;
        uint256 oraclePriceOperate;
        uint256 oraclePriceLiquidate;
        address rebalancer;
    }

    struct CurrentBranchState {
        uint256 status; // if 0 then not liquidated, if 1 then liquidated, if 2 then merged, if 3 then closed
        int256 minimaTick;
        uint256 debtFactor;
        uint256 partials;
        uint256 debtLiquidity;
        uint256 baseBranchId;
        int256 baseBranchMinima;
    }

    struct ExchangePricesAndRates {
        uint256 lastStoredLiquiditySupplyExchangePrice;
        uint256 lastStoredLiquidityBorrowExchangePrice;
        uint256 lastStoredVaultSupplyExchangePrice;
        uint256 lastStoredVaultBorrowExchangePrice;
        uint256 liquiditySupplyExchangePrice;
        uint256 liquidityBorrowExchangePrice;
        uint256 vaultSupplyExchangePrice;
        uint256 vaultBorrowExchangePrice;
        uint256 supplyRateVault;
        uint256 borrowRateVault;
        uint256 supplyRateLiquidity;
        uint256 borrowRateLiquidity;
        uint256 rewardsRate;
    }

    struct LimitsAndAvailability {
        uint256 withdrawLimit;
        uint256 withdrawableUntilLimit;
        uint256 withdrawable;
        uint256 borrowLimit;
        uint256 borrowableUntilLimit;
        uint256 borrowable;
        uint256 borrowLimitUtilization;
        uint256 minimumBorrowing;
    }

    struct LiquidationStruct {
        address vault;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 tokenInAmtOne;
        uint256 tokenOutAmtOne;
        uint256 tokenInAmtTwo;
        uint256 tokenOutAmtTwo;
    }

    struct TotalSupplyAndBorrow {
        uint256 totalSupplyVault;
        uint256 totalBorrowVault;
        uint256 totalSupplyLiquidity;
        uint256 totalBorrowLiquidity;
        uint256 absorbedSupply;
        uint256 absorbedBorrow;
    }

    struct UserBorrowData {
        bool modeWithInterest;
        uint256 borrow;
        uint256 borrowLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseBorrowLimit;
        uint256 maxBorrowLimit;
        uint256 borrowableUntilLimit;
        uint256 borrowable;
        uint256 borrowLimitUtilization;
    }

    struct UserPosition {
        uint256 nftId;
        address owner;
        bool isLiquidated;
        bool isSupplyPosition;
        int256 tick;
        uint256 tickId;
        uint256 beforeSupply;
        uint256 beforeBorrow;
        uint256 beforeDustBorrow;
        uint256 supply;
        uint256 borrow;
        uint256 dustBorrow;
    }

    struct UserSupplyData {
        bool modeWithInterest;
        uint256 supply;
        uint256 withdrawalLimit;
        uint256 lastUpdateTimestamp;
        uint256 expandPercent;
        uint256 expandDuration;
        uint256 baseWithdrawalLimit;
        uint256 withdrawableUntilLimit;
        uint256 withdrawable;
    }

    struct VaultEntireData {
        address vault;
        ConstantViews constantVariables;
        Configs configs;
        ExchangePricesAndRates exchangePricesAndRates;
        TotalSupplyAndBorrow totalSupplyAndBorrow;
        LimitsAndAvailability limitsAndAvailability;
        VaultState vaultState;
        UserSupplyData liquidityUserSupplyData;
        UserBorrowData liquidityUserBorrowData;
    }

    struct VaultState {
        uint256 totalPositions;
        int256 topTick;
        uint256 currentBranch;
        uint256 totalBranch;
        uint256 totalBorrow;
        uint256 totalSupply;
        CurrentBranchState currentBranchState;
    }

    function FACTORY() external view returns (address);
    function LIQUIDITY() external view returns (address);
    function LIQUIDITY_RESOLVER() external view returns (IFluidLiquidityResolver);
    function calculateDoubleIntUintMapping(uint256 slot_, int256 key1_, uint256 key2_) external pure returns (bytes32);
    function calculateStorageSlotIntMapping(uint256 slot_, int256 key_) external pure returns (bytes32);
    function calculateStorageSlotUintMapping(uint256 slot_, uint256 key_) external pure returns (bytes32);
    function getAbsorbedLiquidityRaw(IFluidVault vault_) external view returns (uint256);
    function getAllVaultsAddresses() external view returns (IFluidVault[] memory vaults_);
    function getAllVaultsLiquidation() external returns (LiquidationStruct[] memory liquidationsData_);
    function getBranchDataRaw(IFluidVault vault_, uint256 branch_) external view returns (uint256);
    function getMultipleVaultsLiquidation(address[] memory vaults_, uint256[] memory tokensInAmt_)
        external
        returns (LiquidationStruct[] memory liquidationsData_);
    function getPositionDataRaw(IFluidVault vault_, uint256 positionId_) external view returns (uint256);
    function getRateRaw(IFluidVault vault_) external view returns (uint256);
    function getRebalancer(IFluidVault vault_) external view returns (address);
    function getTickDataRaw(IFluidVault vault_, int256 tick_) external view returns (uint256);
    function getTickHasDebtRaw(IFluidVault vault_, int256 key_) external view returns (uint256);
    function getTickIdDataRaw(IFluidVault vault_, int256 tick_, uint256 id_) external view returns (uint256);
    function getTokenConfig(uint256 nftId_) external view returns (uint256);
    function getTotalVaults() external view returns (uint256);
    function getVaultAbsorb(IFluidVault vault_) external returns (AbsorbStruct memory absorbData_);
    function getVaultAddress(uint256 vaultId_) external view returns (IFluidVault vault_);
    function getVaultEntireData(IFluidVault vault_) external view returns (VaultEntireData memory vaultData_);
    function getVaultId(IFluidVault vault_) external view returns (uint256 id_);
    function getVaultLiquidation(IFluidVault vault_, uint256 tokenInAmt_) external returns (LiquidationStruct memory liquidationData_);
    function getVaultState(IFluidVault vault_) external view returns (VaultState memory vaultState_);
    function getVaultVariables2Raw(IFluidVault vault_) external view returns (uint256);
    function getVaultVariablesRaw(IFluidVault vault_) external view returns (uint256);
    function getVaultsAbsorb() external returns (AbsorbStruct[] memory absorbData_);
    function getVaultsAbsorb(address[] memory vaults_) external returns (AbsorbStruct[] memory absorbData_);
    function getVaultsEntireData(address[] memory vaults_) external view returns (VaultEntireData[] memory vaultsData_);
    function getVaultsEntireData() external view returns (VaultEntireData[] memory vaultsData_);
    function normalSlot(uint256 slot_) external pure returns (bytes32);
    function positionByNftId(uint256 nftId_) external view returns (UserPosition memory userPosition_, VaultEntireData memory vaultData_);
    function positionsByUser(address user_)
        external
        view
        returns (UserPosition[] memory userPositions_, VaultEntireData[] memory vaultsData_);
    function positionsNftIdOfUser(address user_) external view returns (uint256[] memory nftIds_);
    function tickHelper(uint256 tickRaw_) external pure returns (int256 tick);
    function totalPositions() external view returns (uint256);
    function vaultByNftId(uint256 nftId_) external view returns (IFluidVault vault_);

}

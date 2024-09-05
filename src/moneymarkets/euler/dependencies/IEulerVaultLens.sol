// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IEulerVault } from "./IEulerVault.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IEulerVaultLens {

    type InterestRateModelType is uint8;

    struct AssetPriceInfo {
        bool queryFailure;
        bytes queryFailureReason;
        uint256 timestamp;
        address oracle;
        IERC20 asset;
        address unitOfAccount;
        uint256 amountIn;
        uint256 amountOutMid;
        uint256 amountOutBid;
        uint256 amountOutAsk;
    }

    struct InterestRateInfo {
        uint256 cash;
        uint256 borrows;
        uint256 borrowSPY;
        uint256 supplySPY;
        uint256 borrowAPY;
        uint256 supplyAPY;
    }

    struct InterestRateModelDetailedInfo {
        address interestRateModel;
        InterestRateModelType interestRateModelType;
        bytes interestRateModelParams;
    }

    struct LTVInfo {
        IERC20 collateral;
        uint256 borrowLTV;
        uint256 liquidationLTV;
        uint256 initialLiquidationLTV;
        uint256 targetTimestamp;
        uint256 rampDuration;
    }

    struct OracleDetailedInfo {
        address oracle;
        string name;
        bytes oracleInfo;
    }

    struct RewardAmountInfo {
        uint256 epoch;
        uint256 epochStart;
        uint256 epochEnd;
        uint256 rewardAmount;
    }

    struct VaultInfoFull {
        uint256 timestamp;
        IEulerVault vault;
        string vaultName;
        string vaultSymbol;
        uint256 vaultDecimals;
        IERC20 asset;
        string assetName;
        string assetSymbol;
        uint256 assetDecimals;
        address unitOfAccount;
        string unitOfAccountName;
        string unitOfAccountSymbol;
        uint256 unitOfAccountDecimals;
        uint256 totalShares;
        uint256 totalCash;
        uint256 totalBorrowed;
        uint256 totalAssets;
        uint256 accumulatedFeesShares;
        uint256 accumulatedFeesAssets;
        address governorFeeReceiver;
        address protocolFeeReceiver;
        uint256 protocolFeeShare;
        uint256 interestFee;
        uint256 hookedOperations;
        uint256 configFlags;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 maxLiquidationDiscount;
        uint256 liquidationCoolOffTime;
        address dToken;
        address oracle;
        address interestRateModel;
        address hookTarget;
        address evc;
        address protocolConfig;
        address balanceTracker;
        address permit2;
        address creator;
        address governorAdmin;
        VaultInterestRateModelInfo irmInfo;
        LTVInfo[] collateralLTVInfo;
        AssetPriceInfo liabilityPriceInfo;
        AssetPriceInfo[] collateralPriceInfo;
        OracleDetailedInfo oracleInfo;
        AssetPriceInfo backupAssetPriceInfo;
        OracleDetailedInfo backupAssetOracleInfo;
    }

    struct VaultInterestRateModelInfo {
        bool queryFailure;
        bytes queryFailureReason;
        IEulerVault vault;
        address interestRateModel;
        InterestRateInfo[] interestRateInfo;
        InterestRateModelDetailedInfo interestRateModelInfo;
    }

    struct VaultRewardInfo {
        uint256 timestamp;
        IEulerVault vault;
        IERC20 reward;
        string rewardName;
        string rewardSymbol;
        uint8 rewardDecimals;
        address balanceTracker;
        uint256 epochDuration;
        uint256 currentEpoch;
        uint256 totalRewardedEligible;
        uint256 totalRewardRegistered;
        uint256 totalRewardClaimed;
        RewardAmountInfo[] epochInfoPrevious;
        RewardAmountInfo[] epochInfoUpcoming;
    }

    function TTL_ERROR() external view returns (int256);
    function TTL_INFINITY() external view returns (int256);
    function TTL_LIQUIDATION() external view returns (int256);
    function TTL_MORE_THAN_ONE_YEAR() external view returns (int256);
    function getAssetPriceInfo(IERC20 asset, address unitOfAccount) external view returns (AssetPriceInfo memory);
    function getControllerAssetPriceInfo(address controller, IERC20 asset) external view returns (AssetPriceInfo memory);
    function getRecognizedCollateralsLTVInfo(IEulerVault vault) external view returns (LTVInfo[] memory);
    function getRewardVaultInfo(IEulerVault vault, IERC20 reward, uint256 numberOfEpochs) external view returns (VaultRewardInfo memory);
    function getVaultInfoFull(IEulerVault vault) external view returns (VaultInfoFull memory);
    function getVaultInterestRateModelInfo(IEulerVault vault, uint256[] memory cash, uint256[] memory borrows)
        external
        view
        returns (VaultInterestRateModelInfo memory);
    function getVaultKinkInterestRateModelInfo(IEulerVault vault) external view returns (VaultInterestRateModelInfo memory);
    function irmLens() external view returns (address);
    function oracleLens() external view returns (address);

}

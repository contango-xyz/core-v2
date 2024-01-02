//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IExactlyPreviewer {

    struct Position {
        uint256 principal;
        uint256 fee;
    }

    struct ClaimableReward {
        address asset;
        string assetName;
        string assetSymbol;
        uint256 amount;
    }

    struct FixedPool {
        uint256 maturity;
        uint256 borrowed;
        uint256 supplied;
        uint256 available;
        uint256 utilization;
        uint256 depositRate;
        uint256 minBorrowRate;
        uint256 optimalDeposit;
    }

    struct FixedPosition {
        uint256 maturity;
        uint256 previewValue;
        Position position;
    }

    struct FixedPreview {
        uint256 maturity;
        uint256 assets;
        uint256 utilization;
    }

    struct InterestRateModel {
        address id;
        uint256 fixedCurveA;
        int256 fixedCurveB;
        uint256 fixedMaxUtilization;
        uint256 floatingCurveA;
        int256 floatingCurveB;
        uint256 floatingMaxUtilization;
    }

    struct MarketAccount {
        address market;
        string symbol;
        uint8 decimals;
        address asset;
        string assetName;
        string assetSymbol;
        InterestRateModel interestRateModel;
        uint256 usdPrice;
        uint256 penaltyRate;
        uint256 adjustFactor;
        uint8 maxFuturePools;
        FixedPool[] fixedPools;
        RewardRate[] rewardRates;
        uint256 floatingBorrowRate;
        uint256 floatingUtilization;
        uint256 floatingBackupBorrowed;
        uint256 floatingAvailableAssets;
        uint256 totalFloatingBorrowAssets;
        uint256 totalFloatingDepositAssets;
        uint256 totalFloatingBorrowShares;
        uint256 totalFloatingDepositShares;
        bool isCollateral;
        uint256 maxBorrowAssets;
        uint256 floatingBorrowShares;
        uint256 floatingBorrowAssets;
        uint256 floatingDepositShares;
        uint256 floatingDepositAssets;
        FixedPosition[] fixedDepositPositions;
        FixedPosition[] fixedBorrowPositions;
        ClaimableReward[] claimableRewards;
    }

    struct RewardRate {
        address asset;
        string assetName;
        string assetSymbol;
        uint256 usdPrice;
        uint256 borrow;
        uint256 floatingDeposit;
        uint256[] maturities;
    }

    function auditor() external view returns (address);
    function basePriceFeed() external view returns (address);
    function exactly(address account) external view returns (MarketAccount[] memory data);
    function previewBorrowAtAllMaturities(address market, uint256 assets) external view returns (FixedPreview[] memory previews);
    function previewBorrowAtMaturity(address market, uint256 maturity, uint256 assets) external view returns (FixedPreview memory);
    function previewDepositAtAllMaturities(address market, uint256 assets) external view returns (FixedPreview[] memory previews);
    function previewDepositAtMaturity(address market, uint256 maturity, uint256 assets) external view returns (FixedPreview memory);
    function previewRepayAtMaturity(address market, uint256 maturity, uint256 positionAssets, address borrower)
        external
        view
        returns (FixedPreview memory);
    function previewWithdrawAtMaturity(address market, uint256 maturity, uint256 positionAssets, address owner)
        external
        view
        returns (FixedPreview memory);

}

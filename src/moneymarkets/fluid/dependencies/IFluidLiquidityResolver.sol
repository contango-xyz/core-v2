// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IFluidLiquidityResolver {

    struct OverallTokenData {
        uint256 borrowRate;
        uint256 supplyRate;
        uint256 fee;
        uint256 lastStoredUtilization;
        uint256 storageUpdateThreshold;
        uint256 lastUpdateTimestamp;
        uint256 supplyExchangePrice;
        uint256 borrowExchangePrice;
        uint256 supplyRawInterest;
        uint256 supplyInterestFree;
        uint256 borrowRawInterest;
        uint256 borrowInterestFree;
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 revenue;
        uint256 maxUtilization;
        RateData rateData;
    }

    struct RateData {
        uint256 version;
        RateDataV1Params rateDataV1;
        RateDataV2Params rateDataV2;
    }

    struct RateDataV1Params {
        IERC20 token;
        uint256 kink;
        uint256 rateAtUtilizationZero;
        uint256 rateAtUtilizationKink;
        uint256 rateAtUtilizationMax;
    }

    struct RateDataV2Params {
        IERC20 token;
        uint256 kink1;
        uint256 kink2;
        uint256 rateAtUtilizationZero;
        uint256 rateAtUtilizationKink1;
        uint256 rateAtUtilizationKink2;
        uint256 rateAtUtilizationMax;
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

    error FluidLiquidityCalcsError(uint256 errorId_);
    error FluidLiquidityResolver__AddressZero();

    function LIQUIDITY() external view returns (address);
    function getAllOverallTokensData() external view returns (OverallTokenData[] memory overallTokensData_);
    function getConfigs2(IERC20 token_) external view returns (uint256);
    function getExchangePricesAndConfig(IERC20 token_) external view returns (uint256);
    function getOverallTokenData(IERC20 token_) external view returns (OverallTokenData memory overallTokenData_);
    function getOverallTokensData(address[] memory tokens_) external view returns (OverallTokenData[] memory overallTokensData_);
    function getRateConfig(IERC20 token_) external view returns (uint256);
    function getRevenue(IERC20 token_) external view returns (uint256 revenueAmount_);
    function getRevenueCollector() external view returns (address);
    function getStatus() external view returns (uint256);
    function getTokenRateData(IERC20 token_) external view returns (RateData memory rateData_);
    function getTokensRateData(address[] memory tokens_) external view returns (RateData[] memory rateDatas_);
    function getTotalAmounts(IERC20 token_) external view returns (uint256);
    function getUserBorrow(address user_, IERC20 token_) external view returns (uint256);
    function getUserBorrowData(address user_, IERC20 token_)
        external
        view
        returns (UserBorrowData memory userBorrowData_, OverallTokenData memory overallTokenData_);
    function getUserClass(address user_) external view returns (uint256);
    function getUserMultipleBorrowData(address user_, address[] memory tokens_)
        external
        view
        returns (UserBorrowData[] memory userBorrowingsData_, OverallTokenData[] memory overallTokensData_);
    function getUserMultipleBorrowSupplyData(address user_, address[] memory supplyTokens_, address[] memory borrowTokens_)
        external
        view
        returns (
            UserSupplyData[] memory userSuppliesData_,
            OverallTokenData[] memory overallSupplyTokensData_,
            UserBorrowData[] memory userBorrowingsData_,
            OverallTokenData[] memory overallBorrowTokensData_
        );
    function getUserMultipleSupplyData(address user_, address[] memory tokens_)
        external
        view
        returns (UserSupplyData[] memory userSuppliesData_, OverallTokenData[] memory overallTokensData_);
    function getUserSupply(address user_, IERC20 token_) external view returns (uint256);
    function getUserSupplyData(address user_, IERC20 token_)
        external
        view
        returns (UserSupplyData memory userSupplyData_, OverallTokenData memory overallTokenData_);
    function isAuth(address auth_) external view returns (uint256);
    function isGuardian(address guardian_) external view returns (uint256);
    function listedTokens() external view returns (address[] memory listedTokens_);

}

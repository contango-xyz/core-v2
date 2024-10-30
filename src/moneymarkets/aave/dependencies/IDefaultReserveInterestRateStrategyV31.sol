// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IDefaultReserveInterestRateStrategyV31 {

    struct CalculateInterestRatesParams {
        uint256 unbacked;
        uint256 liquidityAdded;
        uint256 liquidityTaken;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 averageStableBorrowRate;
        uint256 reserveFactor;
        address reserve;
        bool usingVirtualBalance;
        uint256 virtualUnderlyingBalance;
    }

    struct InterestRateData {
        uint16 optimalUsageRatio;
        uint32 baseVariableBorrowRate;
        uint32 variableRateSlope1;
        uint32 variableRateSlope2;
    }

    struct InterestRateDataRay {
        uint256 optimalUsageRatio;
        uint256 baseVariableBorrowRate;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
    }

    event RateDataUpdate(
        address indexed reserve,
        uint256 optimalUsageRatio,
        uint256 baseVariableBorrowRate,
        uint256 variableRateSlope1,
        uint256 variableRateSlope2
    );

    function ADDRESSES_PROVIDER() external view returns (address);
    function MAX_BORROW_RATE() external view returns (uint256);
    function MAX_OPTIMAL_POINT() external view returns (uint256);
    function MIN_OPTIMAL_POINT() external view returns (uint256);
    function calculateInterestRates(CalculateInterestRatesParams memory params) external view returns (uint256, uint256, uint256);
    function getBaseVariableBorrowRate(address reserve) external view returns (uint256);
    function getInterestRateData(address reserve) external view returns (InterestRateDataRay memory);
    function getInterestRateDataBps(address reserve) external view returns (InterestRateData memory);
    function getMaxVariableBorrowRate(address reserve) external view returns (uint256);
    function getOptimalUsageRatio(address reserve) external view returns (uint256);
    function getVariableRateSlope1(address reserve) external view returns (uint256);
    function getVariableRateSlope2(address reserve) external view returns (uint256);
    function setInterestRateParams(address reserve, bytes memory rateData) external;
    function setInterestRateParams(address reserve, InterestRateData memory rateData) external;

}

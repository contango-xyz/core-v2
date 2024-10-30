// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IDefaultReserveInterestRateStrategyV3 {

    struct CalculateInterestRatesParams {
        uint256 unbacked;
        uint256 liquidityAdded;
        uint256 liquidityTaken;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 averageStableBorrowRate;
        uint256 reserveFactor;
        address reserve;
        address aToken;
    }

    function ADDRESSES_PROVIDER() external view returns (address);
    function MAX_EXCESS_STABLE_TO_TOTAL_DEBT_RATIO() external view returns (uint256);
    function MAX_EXCESS_USAGE_RATIO() external view returns (uint256);
    function OPTIMAL_STABLE_TO_TOTAL_DEBT_RATIO() external view returns (uint256);
    function OPTIMAL_USAGE_RATIO() external view returns (uint256);
    function calculateInterestRates(CalculateInterestRatesParams memory params) external view returns (uint256, uint256, uint256);
    function getBaseStableBorrowRate() external view returns (uint256);
    function getBaseVariableBorrowRate() external view returns (uint256);
    function getMaxVariableBorrowRate() external view returns (uint256);
    function getStableRateExcessOffset() external view returns (uint256);
    function getStableRateSlope1() external view returns (uint256);
    function getStableRateSlope2() external view returns (uint256);
    function getVariableRateSlope1() external view returns (uint256);
    function getVariableRateSlope2() external view returns (uint256);

}

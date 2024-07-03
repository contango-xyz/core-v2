// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IInterestRateModel {

    struct Parameters {
        uint256 minRate;
        uint256 naturalRate;
        uint256 maxUtilization;
        uint256 naturalUtilization;
        uint256 growthSpeed;
        uint256 sigmoidSpeed;
        uint256 spreadFactor;
        uint256 maturitySpeed;
        int256 timePreference;
        uint256 fixedAllocation;
        uint256 maxRate;
    }

    error AlreadyMatured();
    error UtilizationExceeded();

    function fixedAllocation() external view returns (uint256);
    function fixedBorrowRate(uint256 maturity, uint256 amount, uint256 borrowed, uint256 supplied, uint256)
        external
        view
        returns (uint256);
    function fixedCurveA() external view returns (uint256);
    function fixedCurveB() external view returns (int256);
    function fixedMaxUtilization() external view returns (uint256);
    function fixedRate(uint256 maturity, uint256 maxPools, uint256 uFixed, uint256 uFloating, uint256 uGlobal)
        external
        view
        returns (uint256);
    function floatingCurveA() external view returns (uint256);
    function floatingCurveB() external view returns (int256);
    function floatingMaxUtilization() external view returns (uint256);
    function floatingRate(uint256 uFloating, uint256 uGlobal) external view returns (uint256);
    function floatingRate(uint256) external view returns (uint256);
    function growthSpeed() external view returns (int256);
    function market() external view returns (address);
    function maturitySpeed() external view returns (int256);
    function maxRate() external view returns (uint256);
    function minFixedRate(uint256, uint256, uint256) external view returns (uint256 rate, uint256 utilization);
    function naturalUtilization() external view returns (uint256);
    function parameters() external view returns (Parameters memory);
    function sigmoidSpeed() external view returns (int256);
    function spreadFactor() external view returns (int256);
    function timePreference() external view returns (int256);

}

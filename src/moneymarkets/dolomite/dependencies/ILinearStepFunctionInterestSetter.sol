// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface ILinearStepFunctionInterestSetter {

    struct InterestRate {
        uint256 value;
    }

    function LOWER_OPTIMAL_PERCENT() external view returns (uint256);
    function UPPER_OPTIMAL_PERCENT() external view returns (uint256);
    function getInterestRate(address, uint256 _borrowWei, uint256 _supplyWei) external view returns (InterestRate memory);

}

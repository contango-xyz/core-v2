//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IInterestRateModel {

    function floatingRate(uint256 utilization) external view returns (uint256);

}

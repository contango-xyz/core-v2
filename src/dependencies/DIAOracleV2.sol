// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface DIAOracleV2 {

    function getValue(string memory key) external view returns (uint128 value, uint128 timestamp);

}

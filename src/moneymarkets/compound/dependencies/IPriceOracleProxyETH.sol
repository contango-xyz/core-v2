// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IAggregatorV2V3 } from "../../../dependencies/Chainlink.sol";

import "./ICToken.sol";

interface IPriceOracleProxyETH {

    type AggregatorBase is uint8;

    function ethUsdAggregator() external view returns (IAggregatorV2V3);
    function getUnderlyingPrice(ICToken cToken) external view returns (uint256);

}

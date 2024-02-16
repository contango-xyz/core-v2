//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ICToken.sol";

interface IChainlinkPriceOracle {

    function baseUnits(string memory) external view returns (uint256);
    function getPrice(ICToken cToken) external view returns (uint256);
    function getUnderlyingPrice(address cToken) external view returns (uint256);
    function isPriceOracle() external view returns (bool);
    function priceFeeds(string memory) external view returns (address);

}

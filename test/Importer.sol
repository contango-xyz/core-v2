//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Force solc/typechain to compile test only dependencies
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "src/moneymarkets/aave/dependencies/IPoolDataProviderV3.sol";
import "src/moneymarkets/exactly/dependencies/IExactlyPreviewer.sol";

// Stubs
import { ChainlinkAggregatorV2V3Mock } from "test/stub/ChainlinkAggregatorV2V3Mock.sol";
import { UniswapPoolStub } from "test/stub/UniswapPoolStub.sol";

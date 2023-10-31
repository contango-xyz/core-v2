// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/Vm.sol";

enum Network {
    LocalhostArbitrum,
    LocalhostOptimism,
    LocalhostPolygon,
    LocalhostMainnet,
    Mainnet,
    Arbitrum,
    Optimism,
    Polygon
}

function toString(Network network) pure returns (string memory) {
    if (network == Network.Arbitrum) return "arbitrum-one";
    if (network == Network.Optimism) return "optimism";
    if (network == Network.Polygon) return "matic";
    if (network == Network.Mainnet) return "mainnet";
    if (network == Network.LocalhostArbitrum) return "localhost-arbitrum";
    if (network == Network.LocalhostOptimism) return "localhost-optimism";
    if (network == Network.LocalhostPolygon) return "localhost-matic";
    if (network == Network.LocalhostMainnet) return "localhost-mainnet";
    revert("Unsupported network");
}

function isArbitrum(Network network) pure returns (bool) {
    return network == Network.Arbitrum || network == Network.LocalhostArbitrum;
}

function isOptimism(Network network) pure returns (bool) {
    return network == Network.Optimism || network == Network.LocalhostOptimism;
}

function isPolygon(Network network) pure returns (bool) {
    return network == Network.Polygon || network == Network.LocalhostPolygon;
}

function isMainnet(Network network) pure returns (bool) {
    return network == Network.Mainnet || network == Network.LocalhostMainnet;
}

function isLocalhost(Network network) pure returns (bool) {
    return network == Network.LocalhostArbitrum || network == Network.LocalhostOptimism || network == Network.LocalhostPolygon
        || network == Network.LocalhostMainnet;
}

using { toString, isOptimism, isArbitrum, isLocalhost, isPolygon, isMainnet } for Network global;

function currentNetwork() view returns (Network) {
    if (block.chainid == 1) return Network.Mainnet;
    if (block.chainid == 10) return Network.Optimism;
    if (block.chainid == 137) return Network.Polygon;
    if (block.chainid == 42_161) return Network.Arbitrum;
    if (block.chainid == 31_337) return Network.LocalhostArbitrum;
    if (block.chainid == 31_338) return Network.LocalhostOptimism;
    if (block.chainid == 31_339) return Network.LocalhostMainnet;
    if (block.chainid == 31_340) return Network.LocalhostPolygon;
    revert(
        string.concat("Unsupported network, chainId=", Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).toString(block.chainid))
    );
}

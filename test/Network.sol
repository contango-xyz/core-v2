// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";

enum Network {
    LocalhostArbitrum,
    LocalhostOptimism,
    LocalhostPolygon,
    LocalhostMainnet,
    Mainnet,
    Arbitrum,
    Optimism,
    Polygon,
    PolygonZK,
    Gnosis,
    Base
}

function toString(Network network) pure returns (string memory) {
    if (network == Network.Arbitrum) return "arbitrum-one";
    if (network == Network.Optimism) return "optimism";
    if (network == Network.Polygon) return "matic";
    if (network == Network.Mainnet) return "mainnet";
    if (network == Network.PolygonZK) return "polygon-zk";
    if (network == Network.Gnosis) return "gnosis";
    if (network == Network.Base) return "base";
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

function isGnosis(Network network) pure returns (bool) {
    return network == Network.Gnosis;
}

function isBase(Network network) pure returns (bool) {
    return network == Network.Base;
}

function isPolygonZK(Network network) pure returns (bool) {
    return network == Network.PolygonZK;
}

function isLocalhost(Network network) pure returns (bool) {
    return network == Network.LocalhostArbitrum || network == Network.LocalhostOptimism || network == Network.LocalhostPolygon
        || network == Network.LocalhostMainnet;
}

using { toString, isOptimism, isArbitrum, isLocalhost, isPolygon, isMainnet, isGnosis, isBase, isPolygonZK } for Network global;

function currentNetwork() view returns (Network) {
    return networkFromChainId(block.chainid);
}

function networkFromChainId(uint256 chainId) pure returns (Network) {
    if (chainId == 1) return Network.Mainnet;
    if (chainId == 10) return Network.Optimism;
    if (chainId == 100) return Network.Gnosis;
    if (chainId == 137) return Network.Polygon;
    if (chainId == 1101) return Network.PolygonZK;
    if (chainId == 8453) return Network.Base;
    if (chainId == 42_161) return Network.Arbitrum;

    if (chainId == 31_337) return Network.LocalhostArbitrum;
    if (chainId == 31_338) return Network.LocalhostOptimism;
    if (chainId == 31_339) return Network.LocalhostMainnet;
    if (chainId == 31_340) return Network.LocalhostPolygon;
    revert(string.concat("Unsupported network, chainId=", Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).toString(chainId)));
}

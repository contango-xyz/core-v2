// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";

enum Network {
    LocalhostArbitrum,
    LocalhostOptimism,
    LocalhostMainnet,
    Mainnet,
    Arbitrum,
    Optimism,
    Polygon,
    PolygonZK,
    Gnosis,
    Base,
    Bsc,
    Linea,
    Scroll,
    Avalanche
}

function toString(Network network) pure returns (string memory) {
    if (network == Network.Arbitrum) return "arbitrum-one";
    if (network == Network.Optimism) return "optimism";
    if (network == Network.Polygon) return "matic";
    if (network == Network.Mainnet) return "mainnet";
    if (network == Network.PolygonZK) return "polygon-zk";
    if (network == Network.Gnosis) return "gnosis";
    if (network == Network.Base) return "base";
    if (network == Network.Bsc) return "bsc";
    if (network == Network.Linea) return "linea";
    if (network == Network.Scroll) return "scroll";
    if (network == Network.Avalanche) return "avalanche";
    if (network == Network.LocalhostArbitrum) return "localhost-arbitrum";
    if (network == Network.LocalhostOptimism) return "localhost-optimism";
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
    return network == Network.Polygon;
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

function isBsc(Network network) pure returns (bool) {
    return network == Network.Bsc;
}

function isLinea(Network network) pure returns (bool) {
    return network == Network.Linea;
}

function isScroll(Network network) pure returns (bool) {
    return network == Network.Scroll;
}

function isAvalanche(Network network) pure returns (bool) {
    return network == Network.Avalanche;
}

function isLocalhost(Network network) pure returns (bool) {
    return network == Network.LocalhostArbitrum || network == Network.LocalhostOptimism || network == Network.LocalhostMainnet;
}

function chainId(Network network) pure returns (uint256) {
    if (isMainnet(network)) return 1;
    if (isOptimism(network)) return 10;
    if (isBsc(network)) return 56;
    if (isGnosis(network)) return 100;
    if (isPolygon(network)) return 137;
    if (isPolygonZK(network)) return 1101;
    if (isBase(network)) return 8453;
    if (isArbitrum(network)) return 42_161;
    if (isAvalanche(network)) return 43_114;
    if (isLinea(network)) return 59_144;
    if (isScroll(network)) return 534_352;

    revert("Unsupported network");
}

using {
    toString,
    isOptimism,
    isArbitrum,
    isLocalhost,
    isPolygon,
    isMainnet,
    isGnosis,
    isBase,
    isBsc,
    isPolygonZK,
    isAvalanche,
    isLinea,
    isScroll,
    chainId
} for Network global;

function currentNetwork() view returns (Network) {
    return networkFromChainId(block.chainid);
}

function networkFromChainId(uint256 _chainId) pure returns (Network) {
    if (_chainId == 1) return Network.Mainnet;
    if (_chainId == 10) return Network.Optimism;
    if (_chainId == 56) return Network.Bsc;
    if (_chainId == 100) return Network.Gnosis;
    if (_chainId == 137) return Network.Polygon;
    if (_chainId == 1101) return Network.PolygonZK;
    if (_chainId == 8453) return Network.Base;
    if (_chainId == 42_161) return Network.Arbitrum;
    if (_chainId == 43_114) return Network.Avalanche;
    if (_chainId == 59_144) return Network.Linea;
    if (_chainId == 534_352) return Network.Scroll;

    if (_chainId == 31_337) return Network.LocalhostArbitrum;
    if (_chainId == 31_338) return Network.LocalhostOptimism;
    if (_chainId == 31_339) return Network.LocalhostMainnet;
    revert(string.concat("Unsupported network, chainId=", Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).toString(_chainId)));
}

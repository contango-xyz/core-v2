//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/Proxy.sol";

contract ImmutableBeaconProxy is Proxy {

    UpgradeableBeacon public immutable __beacon;

    constructor(UpgradeableBeacon beacon) {
        __beacon = beacon;
    }

    function _implementation() internal view override returns (address) {
        return __beacon.implementation();
    }

}

//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradeableBeaconWithOwner is UpgradeableBeacon {

    constructor(address implementation, address owner) UpgradeableBeacon(implementation) {
        _transferOwnership(owner);
    }

}

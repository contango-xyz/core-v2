//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Timelock } from "../libraries/DataTypes.sol";

contract UpgradeableBeaconWithOwner is UpgradeableBeacon {

    constructor(address implementation, Timelock owner) UpgradeableBeacon(implementation) {
        _transferOwnership(Timelock.unwrap(owner));
    }

}

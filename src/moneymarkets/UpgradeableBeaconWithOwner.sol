//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { MarketTimelock } from "../libraries/DataTypes.sol";

contract UpgradeableBeaconWithOwner is UpgradeableBeacon {

    constructor(address implementation, MarketTimelock owner) UpgradeableBeacon(implementation) {
        _transferOwnership(MarketTimelock.unwrap(owner));
    }

}

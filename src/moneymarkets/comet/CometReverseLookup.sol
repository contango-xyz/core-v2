//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import { Payload, Timelock, Operator } from "../../libraries/DataTypes.sol";
import { OPERATOR_ROLE } from "../../libraries/Roles.sol";

import "./dependencies/IComet.sol";

interface CometReverseLookupEvents {

    event CometSet(IComet indexed comet, Payload payload);

}

interface CometReverseLookupErrors {

    error CometNotFound(Payload payload);
    error CometAlreadySet(IComet marketId, Payload payload);

}

contract CometReverseLookup is CometReverseLookupEvents, CometReverseLookupErrors, AccessControl {

    uint40 public nextPayload = 1;
    mapping(Payload payload => IComet comet) public comets;
    mapping(IComet comet => Payload payload) public payloads;

    constructor(Timelock timelock, Operator operator) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _grantRole(OPERATOR_ROLE, Timelock.unwrap(timelock));
        _grantRole(OPERATOR_ROLE, Operator.unwrap(operator));
    }

    function setComet(IComet _comet) external onlyRole(OPERATOR_ROLE) returns (Payload payload) {
        if (Payload.unwrap(payloads[_comet]) != bytes5(0)) revert CometAlreadySet(_comet, payloads[_comet]);

        payload = Payload.wrap(bytes5(nextPayload++));
        comets[payload] = _comet;
        payloads[_comet] = payload;
        emit CometSet(_comet, payload);
    }

    function comet(Payload payload) external view returns (IComet comet_) {
        comet_ = comets[payload];
        if (comet_ == IComet(address(0))) revert CometNotFound(payload);
    }

}

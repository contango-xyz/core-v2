//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import { Payload, Timelock } from "../../libraries/DataTypes.sol";

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
    mapping(IERC20 baseAsset => IComet comet) public cometsByBaseAsset;

    constructor(Timelock timelock, IComet[] memory _comets) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        uint40 payload = nextPayload;
        for (uint256 i; i < _comets.length; i++) {
            _setComet(_comets[i], payload++);
        }
        nextPayload = payload;
    }

    function setComet(IComet _comet) external onlyRole(DEFAULT_ADMIN_ROLE) returns (Payload payload) {
        return _setComet(_comet, nextPayload++);
    }

    function _setComet(IComet _comet, uint40 _payload) internal returns (Payload payload) {
        if (Payload.unwrap(payloads[_comet]) != bytes5(0)) revert CometAlreadySet(_comet, payloads[_comet]);

        payload = Payload.wrap(bytes5(_payload));
        comets[payload] = _comet;
        payloads[_comet] = payload;
        cometsByBaseAsset[_comet.baseToken()] = _comet;
        emit CometSet(_comet, payload);
    }

    function comet(Payload payload) external view returns (IComet comet_) {
        comet_ = comets[payload];
        if (comet_ == IComet(address(0))) revert CometNotFound(payload);
    }

}

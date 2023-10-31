//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./dependencies/IMorpho.sol";

import { Payload, Timelock } from "../../libraries/DataTypes.sol";

interface MorphoBlueReverseLookupEvents {

    event MarketSet(Payload, Id);

}

interface MorphoBlueReverseLookupErrors {

    error MarketNotFound(Payload payload);
    error InvalidMarketId(Id marketId);
    error MarkerAlreadySet(Id marketId, Payload payload);

}

contract MorphoBlueReverseLookup is MorphoBlueReverseLookupEvents, MorphoBlueReverseLookupErrors, AccessControl {

    IMorpho public immutable morpho;

    uint256 public nextPayload = 1;
    mapping(Payload payload => Id marketId) private _marketIds;
    mapping(Id marketId => Payload payload) private _payloads;

    constructor(Timelock timelock, IMorpho _morpho) {
        morpho = _morpho;
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function setMarket(Id _marketId) external onlyRole(DEFAULT_ADMIN_ROLE) returns (Payload payload) {
        if (morpho.idToMarketParams(_marketId).loanToken == IERC20(address(0))) revert InvalidMarketId(_marketId);
        if (Payload.unwrap(_payloads[_marketId]) != bytes5(0)) revert MarkerAlreadySet(_marketId, _payloads[_marketId]);

        payload = Payload.wrap(bytes5(uint40(nextPayload++)));
        _marketIds[payload] = _marketId;
        _payloads[_marketId] = payload;
        emit MarketSet(payload, _marketId);
    }

    function marketId(Payload payload) external view returns (Id marketId_) {
        marketId_ = _marketIds[payload];
        if (Id.unwrap(marketId_) == bytes32(0)) revert MarketNotFound(payload);
    }

}

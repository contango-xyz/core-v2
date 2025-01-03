//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/IMorpho.sol";

import { Payload } from "../../libraries/DataTypes.sol";

interface MorphoBlueReverseLookupEvents {

    event MarketSet(Payload indexed payload, MorphoMarketId indexed marketId);

}

interface MorphoBlueReverseLookupErrors {

    error MarketNotFound(Payload payload);
    error InvalidMarketId(MorphoMarketId marketId);
    error MarketAlreadySet(MorphoMarketId marketId, Payload payload);

}

contract MorphoBlueReverseLookup is MorphoBlueReverseLookupEvents, MorphoBlueReverseLookupErrors {

    IMorpho public immutable morpho;

    uint40 public nextPayload = 1;
    mapping(Payload payload => MorphoMarketId marketId) public marketIds;
    mapping(MorphoMarketId marketId => Payload payload) public payloads;

    constructor(IMorpho _morpho) {
        morpho = _morpho;
    }

    function setMarket(MorphoMarketId _marketId) external returns (Payload payload) {
        MarketParams memory params = morpho.idToMarketParams(_marketId);
        if (params.loanToken == IERC20(address(0))) revert InvalidMarketId(_marketId);
        if (Payload.unwrap(payloads[_marketId]) != bytes5(0)) revert MarketAlreadySet(_marketId, payloads[_marketId]);

        payload = Payload.wrap(bytes5(nextPayload++));
        marketIds[payload] = _marketId;
        payloads[_marketId] = payload;
        emit MarketSet(payload, _marketId);
    }

    function marketId(Payload payload) external view returns (MorphoMarketId marketId_) {
        marketId_ = marketIds[payload];
        if (MorphoMarketId.unwrap(marketId_) == bytes32(0)) revert MarketNotFound(payload);
    }

}

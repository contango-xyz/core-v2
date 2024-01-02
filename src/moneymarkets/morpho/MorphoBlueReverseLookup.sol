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
    error OracleNotFound(IERC20 asset);
    error InvalidMarketId(Id marketId);
    error MarketAlreadySet(Id marketId, Payload payload);

}

enum QuoteOracleCcy {
    USD,
    NATIVE
}

struct QuoteOracle {
    address oracle;
    bytes11 oracleType;
    QuoteOracleCcy oracleCcy;
}

contract MorphoBlueReverseLookup is MorphoBlueReverseLookupEvents, MorphoBlueReverseLookupErrors, AccessControl {

    IMorpho public immutable morpho;

    uint40 public nextPayload = 1;
    mapping(Payload payload => Id marketId) private _marketIds;
    mapping(Id marketId => Payload payload) private _payloads;
    mapping(IERC20 asset => Id marketId) private _assetToMarketId;
    mapping(IERC20 asset => QuoteOracle oracleData) private _assetToQuoteOracle;

    constructor(Timelock timelock, IMorpho _morpho) {
        morpho = _morpho;
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function setMarket(Id _marketId) external onlyRole(DEFAULT_ADMIN_ROLE) returns (Payload payload) {
        MarketParams memory params = morpho.idToMarketParams(_marketId);
        if (params.loanToken == IERC20(address(0))) revert InvalidMarketId(_marketId);
        if (Payload.unwrap(_payloads[_marketId]) != bytes5(0)) revert MarketAlreadySet(_marketId, _payloads[_marketId]);
        if (_assetToQuoteOracle[params.loanToken].oracle == address(0)) revert OracleNotFound(params.loanToken);

        payload = Payload.wrap(bytes5(nextPayload++));
        _marketIds[payload] = _marketId;
        _payloads[_marketId] = payload;
        _assetToMarketId[params.collateralToken] = _marketId;
        emit MarketSet(payload, _marketId);
    }

    function setOracle(IERC20 asset, address oracle, bytes11 oracleType, QuoteOracleCcy oracleCcy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assetToQuoteOracle[asset] = QuoteOracle(oracle, oracleType, oracleCcy);
    }

    function setAssetToMarketId(IERC20 asset, Id _marketId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assetToMarketId[asset] = _marketId;
    }

    function marketId(Payload payload) external view returns (Id marketId_) {
        marketId_ = _marketIds[payload];
        if (Id.unwrap(marketId_) == bytes32(0)) revert MarketNotFound(payload);
    }

    function marketId(IERC20 asset) external view returns (Id marketId_) {
        marketId_ = _assetToMarketId[asset];
    }

    function quoteOracle(IERC20 asset) external view returns (QuoteOracle memory quoteOracle_) {
        quoteOracle_ = _assetToQuoteOracle[asset];
    }

}

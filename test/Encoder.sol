//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "src/moneymarkets/aave/dependencies/IPoolDataProviderV3.sol";

import { IContango, IERC20, Instrument } from "src/interfaces/IContango.sol";
import { PositionId, Payload, Symbol, MoneyMarketId, InvalidExpiry, InvalidUInt32, InvalidUInt48 } from "src/libraries/DataTypes.sol";
import { MM_AAVE, MM_SPARK_SKY, MM_MORPHO_BLUE, MM_COMET, MM_EULER, MM_FLUID } from "script/constants.sol";
import { E_MODE, ISOLATION_MODE } from "src/moneymarkets/aave/AaveMoneyMarket.sol";
import { InvalidUInt8 } from "src/libraries/BitFlags.sol";

contract Encoder {

    IContango public immutable contango;
    IPoolDataProviderV3 public immutable aaveDataProvider;
    IPoolDataProviderV3 public immutable sparkDataProvider;

    Payload public payload;

    constructor(IContango _contango, IPoolDataProviderV3 _aaveDataProvider, IPoolDataProviderV3 _sparkDataProvider) {
        contango = _contango;
        aaveDataProvider = _aaveDataProvider;
        sparkDataProvider = _sparkDataProvider;
    }

    function setPayload(Payload _payload) external {
        payload = _payload;
    }

    function encodePositionId(IERC20 base, IERC20 quote, MoneyMarketId mm, uint256 expiry, uint256 number)
        external
        view
        returns (PositionId positionId)
    {
        Symbol symbol = Symbol.wrap(bytes16(abi.encodePacked(base.symbol(), quote.symbol())));
        return encodePositionId(symbol, mm, expiry, number);
    }

    function encodePositionId(Symbol symbol, MoneyMarketId mm, uint256 expiry, uint256 number)
        public
        view
        returns (PositionId positionId)
    {
        bytes1 flags;
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_SPARK_SKY)) flags = _aaveFlags(sparkDataProvider, symbol);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_MORPHO_BLUE)) return encode(symbol, mm, expiry, number, payload);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_COMET)) return encode(symbol, mm, expiry, number, payload);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_EULER)) return encode(symbol, mm, expiry, number, payload);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_FLUID)) return encode(symbol, mm, expiry, number, payload);

        return encode(symbol, mm, expiry, number, flags);
    }

    function _aaveFlags(IPoolDataProviderV3 dataProvider, Symbol symbol) private view returns (bytes1 flags) {
        Instrument memory instrument = contango.instrument(symbol);

        uint256 debtCeiling = dataProvider.getDebtCeiling(address(instrument.base));
        if (debtCeiling != 0) flags = setBit(flags, ISOLATION_MODE);

        uint256 eModeCategory = dataProvider.getReserveEModeCategory(address(instrument.quote));
        if (eModeCategory > 0 && eModeCategory == dataProvider.getReserveEModeCategory(address(instrument.base))) {
            flags = setBit(flags, E_MODE);
        }
    }

}

function encode(Symbol symbol, MoneyMarketId mm, uint256 expiry, uint256 number, bytes1 flags) pure returns (PositionId positionId) {
    if (uint48(number) != number) revert InvalidUInt48(number);
    if (uint32(expiry) != expiry) revert InvalidUInt32(expiry);
    if (expiry == 0) revert InvalidExpiry();

    positionId = PositionId.wrap(
        bytes32(Symbol.unwrap(symbol)) | bytes32(uint256(MoneyMarketId.unwrap(mm))) << 120 | bytes32(uint256(expiry)) << 88
            | bytes32(flags) >> 168 | bytes32(number)
    );
}

function encode(Symbol symbol, MoneyMarketId mm, uint256 expiry, uint256 number, Payload payload) pure returns (PositionId positionId) {
    if (uint48(number) != number) revert InvalidUInt48(number);
    if (uint32(expiry) != expiry) revert InvalidUInt32(expiry);
    if (expiry == 0) revert InvalidExpiry();

    positionId = PositionId.wrap(
        bytes32(Symbol.unwrap(symbol)) | bytes32(uint256(MoneyMarketId.unwrap(mm))) << 120 | bytes32(uint256(expiry)) << 88
            | bytes32(Payload.unwrap(payload)) >> 168 | bytes32(number)
    );
}

function setBit(bytes1 flags, uint256 bit) pure returns (bytes1) {
    if (bit > 7) revert InvalidUInt8(bit);
    bytes1 mask = bytes1(uint8(1 << bit));
    return flags | mask;
}

function baseQuotePayload(uint16 part1, uint16 part2) pure returns (Payload) {
    return Payload.wrap(bytes5(bytes2(part1)) >> 8 | bytes5(bytes2(part2)) >> 24);
}

function flagsAndPayload(bytes1 flags, bytes4 payload) pure returns (Payload) {
    return Payload.wrap(bytes5(flags) | bytes5(payload) >> 8);
}

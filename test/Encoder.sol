//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "src/moneymarkets/aave/dependencies/IPoolDataProvider.sol";

import { IContango, IERC20, Instrument } from "src/interfaces/IContango.sol";
import { PositionId, Payload, Symbol, MoneyMarketId, InvalidExpiry, InvalidUInt32, InvalidUInt48 } from "src/libraries/DataTypes.sol";
import { MM_AAVE, MM_SPARK, MM_MORPHO_BLUE, MM_COMET } from "script/constants.sol";
import { E_MODE, ISOLATION_MODE } from "src/moneymarkets/aave/AaveMoneyMarket.sol";
import { InvalidUInt8 } from "src/libraries/BitFlags.sol";

contract Encoder {

    IContango public immutable contango;
    IPoolDataProvider public immutable aaveDataProvider;
    IPoolDataProvider public immutable sparkDataProvider;

    Payload public payload;

    constructor(IContango _contango, IPoolDataProvider _aaveDataProvider, IPoolDataProvider _sparkDataProvider) {
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
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_AAVE)) flags = _aaveFlags(aaveDataProvider, symbol);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_SPARK)) flags = _aaveFlags(sparkDataProvider, symbol);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_MORPHO_BLUE)) return encode(symbol, mm, expiry, number, payload);
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_COMET)) return encode(symbol, mm, expiry, number, payload);

        return encode(symbol, mm, expiry, number, flags);
    }

    function _aaveFlags(IPoolDataProvider dataProvider, Symbol symbol) private view returns (bytes1 flags) {
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

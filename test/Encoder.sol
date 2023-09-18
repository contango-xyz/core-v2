//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IPool, DataTypes, ReserveConfiguration } from "@aave/core-v3/contracts/protocol/pool/Pool.sol";

import { IContango, Instrument } from "src/interfaces/IContango.sol";
import { PositionId, Symbol, MoneyMarketId, InvalidExpiry, InvalidUInt32, InvalidUInt48 } from "src/libraries/DataTypes.sol";
import { MM_AAVE } from "script/constants.sol";
import { E_MODE, ISOLATION_MODE } from "src/moneymarkets/aave/AaveMoneyMarket.sol";
import { InvalidUInt8 } from "src/libraries/BitFlags.sol";

contract Encoder {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IContango public immutable contango;
    IPool public immutable pool;

    constructor(IContango _contango, IPool _pool) {
        contango = _contango;
        pool = _pool;
    }

    function encodePositionId(Symbol symbol, MoneyMarketId mm, uint256 expiry, uint256 number)
        public
        view
        returns (PositionId positionId)
    {
        bytes1 flags;
        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_AAVE)) {
            Instrument memory instrument = contango.instrument(symbol);

            DataTypes.ReserveData memory baseData = pool.getReserveData(address(instrument.base));
            if (baseData.isolationModeTotalDebt != 0) flags = setBit(flags, ISOLATION_MODE);

            uint256 eModeCategory = pool.getReserveData(address(instrument.quote)).configuration.getEModeCategory();
            if (eModeCategory > 0 && eModeCategory == baseData.configuration.getEModeCategory()) flags = setBit(flags, E_MODE);
        }

        return encode(symbol, mm, expiry, number, flags);
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

function setBit(bytes1 flags, uint256 bit) pure returns (bytes1) {
    if (bit > 7) revert InvalidUInt8(bit);
    bytes1 mask = bytes1(uint8(1 << bit));
    return flags | mask;
}

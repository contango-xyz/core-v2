//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../DataTypes.sol";

error InvalidUInt48(uint256 n);
error InvalidUInt32(uint256 n);
error InvalidExpiry();
error InvalidPositionId();

function decode(PositionId positionId) pure returns (Symbol symbol, MoneyMarket mm, uint32 expiry, uint256 number) {
    bytes32 raw = PositionId.unwrap(positionId);
    symbol = Symbol.wrap(bytes16(raw));
    mm = MoneyMarket.wrap(uint8(bytes1(raw << 128)));
    expiry = (uint32(bytes4(raw << 136)));
    number = uint48(uint256(raw));
}

function getSymbol(PositionId positionId) pure returns (Symbol) {
    return Symbol.wrap(bytes16(PositionId.unwrap(positionId)));
}

function getNumber(PositionId positionId) pure returns (uint256) {
    return uint48(uint256(PositionId.unwrap(positionId)));
}

function getMoneyMarket(PositionId positionId) pure returns (MoneyMarket) {
    return MoneyMarket.wrap(uint8(bytes1(PositionId.unwrap(positionId) << 128)));
}

function getExpiry(PositionId positionId) pure returns (uint32) {
    return (uint32(bytes4(PositionId.unwrap(positionId) << 136)));
}

function isPerp(PositionId positionId) pure returns (bool) {
    return getExpiry(positionId) == type(uint32).max;
}

function isExpired(PositionId positionId) view returns (bool) {
    return block.timestamp >= getExpiry(positionId);
}

function withNumber(PositionId positionId, uint256 number) pure returns (PositionId) {
    if (uint48(number) != number) revert InvalidUInt48(number);
    if (getNumber(positionId) != 0) revert InvalidPositionId();
    return PositionId.wrap(bytes32(uint256(PositionId.unwrap(positionId)) + number));
}

function getFlags(PositionId positionId) pure returns (bytes1) {
    return bytes1(PositionId.unwrap(positionId) << 168);
}

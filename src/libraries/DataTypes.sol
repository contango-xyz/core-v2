//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./extensions/PositionIdExt.sol";

uint256 constant WAD = 1e18;
uint256 constant RAY = 1e27;
uint256 constant PERCENTAGE_UNIT = 1e4;
uint256 constant ONE_HUNDRED_PERCENT = 1e4;

enum Currency {
    None,
    Base,
    Quote
}

type Symbol is bytes16;

type Payload is bytes5;

type PositionId is bytes32;

using {
    decode,
    getSymbol,
    getNumber,
    getMoneyMarket,
    getExpiry,
    isPerp,
    isExpired,
    withNumber,
    getFlags,
    getPayload,
    asUint
} for PositionId global;

type OrderId is bytes32;

type MoneyMarketId is uint8;

function mmEquals(MoneyMarketId a, MoneyMarketId b) pure returns (bool) {
    return MoneyMarketId.unwrap(a) == MoneyMarketId.unwrap(b);
}

using { mmEquals as == } for MoneyMarketId global;

type Timelock is address;

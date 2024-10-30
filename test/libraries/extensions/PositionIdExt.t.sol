//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../../Encoder.sol";
import "../../TestSetup.t.sol";

import "script/constants.sol";

import "src/libraries/DataTypes.sol";

contract PositionIdExtTest is Test {

    function testEncodeDecode(Symbol s, uint8 mmId, uint32 e, uint48 n, bytes1 flags, bytes4 purePayload) public pure {
        vm.assume(e != 0);
        MoneyMarketId m = MoneyMarketId.wrap(mmId);

        bytes5 payload = bytes5(abi.encodePacked(flags, purePayload));

        PositionId positionId = encode(s, m, e, n, Payload.wrap(payload));
        (Symbol _s, MoneyMarketId _m, uint256 _e, uint256 _n) = positionId.decode();

        assertEq(Symbol.unwrap(_s), Symbol.unwrap(s), "symbol");
        assertEq(MoneyMarketId.unwrap(_m), MoneyMarketId.unwrap(m), "mm");
        assertEq(_e, e, "expiry");
        assertEq(_n, n, "n");

        assertEq(Symbol.unwrap(positionId.getSymbol()), Symbol.unwrap(s), "symbol");
        assertEq(MoneyMarketId.unwrap(positionId.getMoneyMarket()), MoneyMarketId.unwrap(m), "mm");
        assertEq(positionId.getExpiry(), e, "expiry");
        if (e == type(uint32).max) assertTrue(positionId.isPerp(), "perp");
        else assertFalse(positionId.isPerp(), "perp");
        assertEq(positionId.getNumber(), n, "n");
        assertEq(flags, positionId.getFlags(), "flags");
        assertEq(payload, Payload.unwrap(positionId.getPayload()), "payload");
        assertEq(purePayload, positionId.getPayloadNoFlags(), "purePayload");
    }

    function testEncodeBoundaries() public pure {
        Symbol s = Symbol.wrap(0xffffffffffffffffffffffffffffffff);
        MoneyMarketId m = MM_COMPOUND;
        uint32 e = type(uint32).max;
        uint128 n = type(uint48).max;

        PositionId positionId = encode(s, m, e, n, 0);
        (Symbol _s, MoneyMarketId _m, uint256 _e, uint256 _n) = positionId.decode();

        assertEq(Symbol.unwrap(_s), Symbol.unwrap(s), "symbol");
        assertEq(MoneyMarketId.unwrap(_m), MoneyMarketId.unwrap(m), "mm");
        assertEq(e, _e, "expiry");
        assertEq(_n, n, "n");
        assertTrue(positionId.isPerp(), "perp");
    }

    function testEncodeNumberOverBoundaries() public {
        uint256 n = uint256(type(uint48).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidUInt48.selector, n));
        encode(Symbol.wrap(""), MM_COMPOUND, 0, n, 0);
    }

    function testEncodeExpiryOverBoundaries() public {
        uint256 e = uint256(type(uint32).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidUInt32.selector, e));
        encode(Symbol.wrap(""), MM_COMPOUND, e, 0, 0);
    }

    function testPartialEncoding(Symbol s, uint8 mmId, uint32 e, uint48 n) public pure {
        vm.assume(e != 0);
        MoneyMarketId m = MoneyMarketId.wrap(mmId);

        PositionId positionId1 = encode(s, m, e, n, 0);
        PositionId positionId2 = encode(s, m, e, 0, 0).withNumber(n);

        assertEq(Symbol.unwrap(positionId1.getSymbol()), Symbol.unwrap(positionId2.getSymbol()), "symbol");
        assertEq(MoneyMarketId.unwrap(positionId1.getMoneyMarket()), MoneyMarketId.unwrap(positionId2.getMoneyMarket()), "mm");
        assertEq(positionId1.getExpiry(), positionId2.getExpiry(), "expiry");
        assertEq(positionId1.getNumber(), positionId2.getNumber(), "n");
    }

}

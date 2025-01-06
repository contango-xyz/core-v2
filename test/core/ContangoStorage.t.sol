//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "../StorageUtils.t.sol";

// slot complexity:
//  if flat, will be bytes32(uint256(uint));
//  if map, will be keccak256(abi.encode(key, uint(slot)));
//  if deep map, will be keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))));
//  if map struct, will be bytes32(uint256(keccak256(abi.encode(key1, keccak256(abi.encode(key0, uint(slot)))))) + structFieldDepth);
contract ContangoStorageTest is BaseTest {

    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;

    Contango internal contango;

    StorageUtils internal su;

    // IMPORTANT: Never change this number, if the slots move cause we add mixins or whatever, discount the gap on the prod contract
    uint256 internal constant GAP = 50_000;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        mm = MM_AAVE;
        contango = env.contango();
        su = new StorageUtils(address(contango));

        vm.prank(TIMELOCK_ADDRESS);
        contango.grantRole(OPERATOR_ROLE, address(this));
    }

    function testInstruments() public {
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        contango.setClosingOnly(instrument.symbol, true);
        bytes32 symbolAndClosingOnly = su.read_bytes32(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP + 7))) + 0));
        assertEq(symbolAndClosingOnly << 128, Symbol.unwrap(instrument.symbol), "instrument.symbol");
        assertEq(uint8(bytes1(symbolAndClosingOnly << 120)), 1, "instrument.closingOnly");

        bytes32 baseAndBaseUnit = su.read_bytes32(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP + 7))) + 1));
        assertEq(address(bytes20(baseAndBaseUnit << 96)), address(instrument.base), "instrument.base");
        assertEq(uint256(baseAndBaseUnit >> 160), instrument.baseUnit, "instrument.baseUnit");

        bytes32 quoteAndQuoteUnit = su.read_bytes32(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP + 7))) + 2));
        assertEq(address(bytes20(quoteAndQuoteUnit << 96)), address(instrument.quote), "instrument.quote");
        assertEq(uint256(quoteAndQuoteUnit >> 160), instrument.quoteUnit, "instrument.quoteUnit");

        // This should fail if we add stuff to the struct and we don't test it
        assertEq(su.read(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP + 7))) + 3)), abi.encode(0), "instrument.empty");
    }

    function testLastOwner() public {
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        UniswapPoolStub poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(1e6);

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            leverage: 2e18,
            cashflowCcy: Currency.Base
        });

        assertEq(su.read_address(bytes32(uint256(keccak256(abi.encode(positionId, GAP + 6))))), address(0), "empty lastOwner");

        env.positionActions().closePosition({ positionId: positionId, quantity: type(uint128).max, cashflow: 0, cashflowCcy: Currency.Base });

        assertEq(su.read_address(bytes32(uint256(keccak256(abi.encode(positionId, GAP + 6))))), TRADER, "lastOwner");
    }

}

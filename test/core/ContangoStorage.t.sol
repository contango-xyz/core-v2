//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/models/FixedFeeModel.sol";

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
    MoneyMarket internal mm;
    UniswapPoolStub internal poolStub;

    Trade internal expectedTrade;
    uint256 internal expectedCollateral;
    uint256 internal expectedDebt;

    Contango internal contango;

    StorageUtils internal su;

    // IMPORTANT: Never change this number, if the slots move cause we add mixins or whatever, discount the gap on the prod contract
    uint256 internal constant GAP = 50_000;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        contango = env.contango();
        su = new StorageUtils(address(contango));

        vm.prank(TIMELOCK_ADDRESS);
        contango.grantRole(OPERATOR_ROLE, address(this));
    }

    function testInstruments() public {
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        contango.setClosingOnly(instrument.symbol, true);
        bytes32 symbolAndClosingOnly = su.read_bytes32(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 0));
        assertEq(symbolAndClosingOnly << 128, Symbol.unwrap(instrument.symbol), "instrument.symbol");
        assertEq(uint8(bytes1(symbolAndClosingOnly << 120)), 1, "instrument.closingOnly");
        assertEq(
            su.read_address(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 1)),
            address(instrument.base),
            "instrument.base"
        );
        assertEq(
            su.read_uint(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 2)),
            10 ** instrument.baseDecimals,
            "instrument.baseUnit"
        );
        assertEq(
            su.read_address(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 3)),
            address(instrument.quote),
            "instrument.quote"
        );
        assertEq(
            su.read_uint(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 4)),
            10 ** instrument.quoteDecimals,
            "instrument.quoteUnit"
        );
        // This should fail if we add stuff to the struct and we don't test it
        assertEq(su.read(bytes32(uint256(keccak256(abi.encode(instrument.symbol, GAP))) + 5)), abi.encode(0), "instrument.empty");
    }

}

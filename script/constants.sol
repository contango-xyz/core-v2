// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "src/libraries/DataTypes.sol";

import "./CreateX.sol";

address constant EGILL = 0x02f73B54ccfBA5c91bf432087D60e4b3a781E497;
address constant ULTRASECRETH = 0x05950b4e68f103d5aBEf20364dE219a247e59C23;
address constant ALFREDO = 0x81FaCe447BF931eB0C7d1e9fFd6C7407cd2aE5a6;
address constant KEEPER = 0x49391E880EA21fC1c3706EB14704ee3944d00bD8;

bytes32 constant INITIAL_SALT = keccak256("Contango V2");
CreateX constant CREATEX = CreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

address payable constant TIMELOCK_ADDRESS = payable(0xc0939a4Ed0129bc5162F6f693935B3F72a46a90D);
Timelock constant TIMELOCK = Timelock.wrap(TIMELOCK_ADDRESS);
address constant POSITION_NFT = 0xC2462f03920D47fC5B9e2C5F0ba5D2ded058fD78;
address constant UNDERLYING_POSITION_FACTORY = 0xDaBA83815404f5e1bc33f5885db7D96F51e127F5;
address constant TANGO_ADDRESS = 0xC760F9782F8ceA5B06D862574464729537159966;
address constant O_TANGO_ADDRESS = 0x007606064f8A40745336F91a1E4345900143756b;
address constant TREASURY = 0x4577b1417BDd10bF1BBFC8CF29180f592b0c3190;
address constant ORACLE = 0x75A2b0ae73f657EB818eC84630FeB8ab3773f32F;

function proxyAddress(string memory name) pure returns (address payable) {
    bytes memory _name = abi.encodePacked(name);

    if (keccak256(_name) == keccak256("ContangoProxy")) return payable(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E);
    if (keccak256(_name) == keccak256("ContangoLensProxy")) return payable(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
    if (keccak256(_name) == keccak256("OrderManagerProxy")) return payable(0xA64f0dbB10c473978C2EFe069da207991e8e3Cb3);
    if (keccak256(_name) == keccak256("VaultProxy")) return payable(0x3F37C7d8e61C000085AAc0515775b06A3412F36b);
    if (keccak256(_name) == keccak256("MaestroProxy")) return payable(0xa6a147946FACAc9E0B99824870B36088764f969F);
    if (keccak256(_name) == keccak256("FeeManagerProxy")) return payable(0xA362611E47eb1888e0f6fD4b5a65A42d7C3eA3A4);

    revert(string.concat("Unknown proxy: ", name));
}

// REMEMBER: Add the new money market to schema.graphql & subgraph/utils.ts
MoneyMarketId constant MM_AAVE = MoneyMarketId.wrap(1);
MoneyMarketId constant MM_COMPOUND = MoneyMarketId.wrap(2);
// MoneyMarketId constant MM_YIELD = MoneyMarketId.wrap(3); // discontinued
MoneyMarketId constant MM_EXACTLY = MoneyMarketId.wrap(4);
MoneyMarketId constant MM_SONNE = MoneyMarketId.wrap(5);
// MoneyMarketId constant MM_MAKER = MoneyMarketId.wrap(6); // not gonna happen
// MoneyMarketId constant MM_SPARK = MoneyMarketId.wrap(7); // Replace with MM_SPARK_SKY
MoneyMarketId constant MM_MORPHO_BLUE = MoneyMarketId.wrap(8);
MoneyMarketId constant MM_AGAVE = MoneyMarketId.wrap(9); // discontinued
MoneyMarketId constant MM_AAVE_V2 = MoneyMarketId.wrap(10);
MoneyMarketId constant MM_RADIANT = MoneyMarketId.wrap(11);
MoneyMarketId constant MM_LODESTAR = MoneyMarketId.wrap(12);
MoneyMarketId constant MM_MOONWELL = MoneyMarketId.wrap(13);
MoneyMarketId constant MM_COMET = MoneyMarketId.wrap(14);
// MoneyMarketId constant MM_GRANARY = MoneyMarketId.wrap(15); Delisted
MoneyMarketId constant MM_SILO = MoneyMarketId.wrap(16);
MoneyMarketId constant MM_DOLOMITE = MoneyMarketId.wrap(17);
MoneyMarketId constant MM_ZEROLEND = MoneyMarketId.wrap(18);
MoneyMarketId constant MM_AAVE_LIDO = MoneyMarketId.wrap(19);
MoneyMarketId constant MM_SILO_2 = MoneyMarketId.wrap(28);
MoneyMarketId constant MM_AAVE_ETHERFI = MoneyMarketId.wrap(29);
MoneyMarketId constant MM_EULER = MoneyMarketId.wrap(30);
MoneyMarketId constant MM_FLUID = MoneyMarketId.wrap(31);
MoneyMarketId constant MM_ZEROLEND_BTC = MoneyMarketId.wrap(32);
MoneyMarketId constant MM_SPARK_SKY = MoneyMarketId.wrap(33);
MoneyMarketId constant MM_ZEROLEND_RWA = MoneyMarketId.wrap(34);
MoneyMarketId constant MM_SILO_BTC = MoneyMarketId.wrap(35);

uint32 constant PERP = type(uint32).max;
uint256 constant DEFAULT_SLIPPAGE_TOLERANCE = 0.001e4;

address constant BOT = 0xC1AF33328E013d1c16e1Fd8b409E2a7cb6c11814;

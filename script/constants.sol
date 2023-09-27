// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "src/libraries/DataTypes.sol";

address constant EGILL = 0x02f73B54ccfBA5c91bf432087D60e4b3a781E497;
address constant ULTRASECRETH = 0x05950b4e68f103d5aBEf20364dE219a247e59C23;
address constant ALFREDO = 0x81FaCe447BF931eB0C7d1e9fFd6C7407cd2aE5a6;

bytes32 constant INITIAL_SALT = keccak256("Contango V2");

address payable constant TIMELOCK_ADDRESS = payable(0xc0939a4Ed0129bc5162F6f693935B3F72a46a90D);
Timelock constant TIMELOCK = Timelock.wrap(TIMELOCK_ADDRESS);
address constant POSITION_NFT = 0xC2462f03920D47fC5B9e2C5F0ba5D2ded058fD78;
address constant UNDERLYING_POSITION_FACTORY = 0xDaBA83815404f5e1bc33f5885db7D96F51e127F5;

function proxyAddress(string memory name) pure returns (address payable) {
    bytes memory _name = abi.encodePacked(name);

    if (keccak256(_name) == keccak256("ContangoProxy")) return payable(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E);
    if (keccak256(_name) == keccak256("OrderManagerProxy")) return payable(0xA64f0dbB10c473978C2EFe069da207991e8e3Cb3);
    if (keccak256(_name) == keccak256("VaultProxy")) return payable(0x3F37C7d8e61C000085AAc0515775b06A3412F36b);
    if (keccak256(_name) == keccak256("MaestroProxy")) return payable(0xa6a147946FACAc9E0B99824870B36088764f969F);
    if (keccak256(_name) == keccak256("FeeManagerProxy")) return payable(0xA362611E47eb1888e0f6fD4b5a65A42d7C3eA3A4);

    revert(string.concat("Unknown proxy: ", name));
}

MoneyMarketId constant MM_AAVE = MoneyMarketId.wrap(1);
MoneyMarketId constant MM_COMPOUND = MoneyMarketId.wrap(2);
MoneyMarketId constant MM_EXACTLY = MoneyMarketId.wrap(4);

uint32 constant PERP = type(uint32).max;
uint256 constant DEFAULT_SLIPPAGE_TOLERANCE = 0.001e4;

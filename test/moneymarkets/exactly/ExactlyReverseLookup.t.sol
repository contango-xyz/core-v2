//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

import "src/moneymarkets/exactly/ExactlyReverseLookup.sol";

contract ExactlyReverseLookupTest is ExactlyReverseLookupEvents, BaseTest {

    Env internal env;

    ExactlyReverseLookup internal sut;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();

        sut = env.deployer().deployExactlyMoneyMarket(env, env.contango()).reverseLookup();
    }

    function testSetMarket() public {
        IERC20 weth = env.token(WETH);

        IExactlyMarket badMarket = IExactlyMarket(address(0xdeadbeef));
        vm.expectRevert(abi.encodeWithSelector(ExactlyReverseLookup.MarketNotListed.selector, badMarket));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(badMarket);

        IExactlyMarket market = IExactlyMarket(address(0xc4d4500326981eacD020e20A81b1c479c161c7EF));
        vm.expectEmit(true, true, true, true);
        emit MarketSet(weth, market);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(market);
    }

}

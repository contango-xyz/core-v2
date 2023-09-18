//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

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
        IMarket market = IMarket(address(0xdeadbeef));

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setMarket(weth, market);

        vm.expectEmit(true, true, true, true);
        emit MarketSet(weth, market);
        vm.prank(TIMELOCK);
        sut.setMarket(weth, market);
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";

import "src/moneymarkets/morpho/MorphoBlueReverseLookup.sol";

contract MorphoBlueReverseLookupTest is MorphoBlueReverseLookupEvents, MorphoBlueReverseLookupErrors, BaseTest {

    Env internal env;

    MorphoBlueReverseLookup internal sut;

    function setUp() public {
        env = provider(Network.Goerli);
        env.init();

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, env.contango()).reverseLookup();
    }

    function testSetMarket() public {
        Id marketId = Id.wrap(0x12a221139da627861202080e40fa0a37e84f91d7c74243390e8708fc5643d6ab);
        Payload expectedPayload = Payload.wrap(bytes5(uint40(1)));

        vm.expectRevert(abi.encodeWithSelector(MarketNotFound.selector, expectedPayload));
        sut.marketId(expectedPayload);

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setMarket(marketId);

        vm.expectEmit(true, true, true, true);
        emit MarketSet(expectedPayload, marketId);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);

        assertEq(Id.unwrap(sut.marketId(expectedPayload)), Id.unwrap(marketId));

        vm.expectRevert(abi.encodeWithSelector(MarkerAlreadySet.selector, marketId, expectedPayload));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);
    }

}

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
        Id marketId = Id.wrap(0x900d90c624f9bd1e1143059c14610bde45ff7d1746c52bf6c094d3568285b661);
        Payload expectedPayload = Payload.wrap(bytes5(uint40(1)));

        vm.expectRevert(abi.encodeWithSelector(MarketNotFound.selector, expectedPayload));
        sut.marketId(expectedPayload);

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setMarket(marketId);

        vm.prank(TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(InvalidMarketId.selector, bytes32("hola")));
        sut.setMarket(Id.wrap("hola"));

        vm.prank(TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OracleNotFound.selector, 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6));
        sut.setMarket(marketId);

        vm.prank(TIMELOCK_ADDRESS);
        sut.setOracle({
            asset: IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6),
            oracle: address(1),
            oracleType: "SOME_TYPE",
            oracleCcy: QuoteOracleCcy.USD
        });

        vm.expectEmit(true, true, true, true);
        emit MarketSet(expectedPayload, marketId);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);

        assertEq(Id.unwrap(sut.marketId(expectedPayload)), Id.unwrap(marketId));

        vm.expectRevert(abi.encodeWithSelector(MarketAlreadySet.selector, marketId, expectedPayload));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);
    }

}

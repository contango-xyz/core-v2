//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

import "src/moneymarkets/morpho/MorphoBlueReverseLookup.sol";

contract MorphoBlueReverseLookupTest is MorphoBlueReverseLookupEvents, MorphoBlueReverseLookupErrors, BaseTest {

    Env internal env;

    MorphoBlueReverseLookup internal sut;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_925_910);

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, env.contango()).reverseLookup();
    }

    function testSetMarket() public {
        MorphoMarketId marketId = MorphoMarketId.wrap(0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc);
        Payload expectedPayload = Payload.wrap(bytes5(uint40(1)));

        vm.expectRevert(abi.encodeWithSelector(MarketNotFound.selector, expectedPayload));
        sut.marketId(expectedPayload);

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setMarket(marketId);

        vm.prank(TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(InvalidMarketId.selector, bytes32("hola")));
        sut.setMarket(MorphoMarketId.wrap("hola"));

        vm.prank(TIMELOCK_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(OracleNotFound.selector, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        sut.setMarket(marketId);

        vm.prank(TIMELOCK_ADDRESS);
        sut.setOracle({
            asset: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            oracle: address(1),
            oracleType: "SOME_TYPE",
            oracleCcy: QuoteOracleCcy.USD
        });

        vm.expectEmit(true, true, true, true);
        emit MarketSet(expectedPayload, marketId);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);

        assertEq(MorphoMarketId.unwrap(sut.marketId(expectedPayload)), MorphoMarketId.unwrap(marketId));

        vm.expectRevert(abi.encodeWithSelector(MarketAlreadySet.selector, marketId, expectedPayload));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setMarket(marketId);
    }

}

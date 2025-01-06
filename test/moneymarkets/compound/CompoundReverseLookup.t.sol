//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

import "src/moneymarkets/compound/CompoundReverseLookup.sol";

contract CompoundReverseLookupTest is CompoundReverseLookupEvents, BaseTest {

    Env internal env;

    CompoundReverseLookup internal sut;

    function testCompoundSetCToken() public {
        env = provider(Network.Mainnet);
        env.init();
        sut = env.deployer().deployCompoundMoneyMarket(env, env.contango()).reverseLookup();

        IERC20 dai = env.token(DAI);

        assertEq(address(sut.cToken(env.token(DAI))), address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643), "DAI cToken");
        assertEq(address(sut.cToken(env.token(USDC))), address(0x39AA39c021dfbaE8faC545936693aC917d5E7563), "USDC cToken");

        ICToken badCToken = ICToken(address(0xdeadbeef));
        vm.expectRevert(abi.encodeWithSelector(CompoundReverseLookup.CTokenNotListed.selector, badCToken));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(badCToken);

        ICToken cToken = ICToken(address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643));
        vm.expectEmit(true, true, true, true);
        emit CTokenSet(dai, cToken);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(cToken);
    }

    function testSonneSetCToken() public {
        env = provider(Network.Optimism);
        env.init();
        sut = env.deployer().deploySonneMoneyMarket(env, env.contango()).reverseLookup();

        IERC20 dai = env.token(DAI);

        assertEq(address(sut.cToken(env.token(DAI))), address(0x5569b83de187375d43FBd747598bfe64fC8f6436), "DAI cToken");
        assertEq(address(sut.cToken(env.token(USDC))), address(0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F), "USDC cToken");

        ICToken badCToken = ICToken(address(0xdeadbeef));
        vm.expectRevert(abi.encodeWithSelector(CompoundReverseLookup.CTokenNotListed.selector, badCToken));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(badCToken);

        ICToken cToken = ICToken(address(0x5569b83de187375d43FBd747598bfe64fC8f6436));
        vm.expectEmit(true, true, true, true);
        emit CTokenSet(dai, cToken);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(cToken);
    }

}

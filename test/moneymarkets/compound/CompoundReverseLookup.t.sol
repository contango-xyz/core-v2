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

        IERC20 weth = env.token(WETH);
        ICToken cToken = ICToken(address(0xdeadbeef));

        assertEq(address(sut.cToken(env.token(DAI))), address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643), "DAI cToken");
        assertEq(address(sut.cToken(env.token(USDC))), address(0x39AA39c021dfbaE8faC545936693aC917d5E7563), "USDC cToken");

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setCToken(weth, cToken);

        vm.expectEmit(true, true, true, true);
        emit CTokenSet(weth, cToken);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(weth, cToken);
    }

    function testSonneSetCToken() public {
        env = provider(Network.Optimism);
        env.init();
        sut = env.deployer().deploySonneMoneyMarket(env, env.contango()).reverseLookup();

        assertEq(address(sut.cToken(env.token(DAI))), address(0x5569b83de187375d43FBd747598bfe64fC8f6436), "DAI cToken");
        assertEq(address(sut.cToken(env.token(USDC))), address(0xEC8FEa79026FfEd168cCf5C627c7f486D77b765F), "USDC cToken");

        IERC20 weth = env.token(WETH);
        ICToken cToken = ICToken(address(0xdeadbeef));

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setCToken(weth, cToken);

        vm.expectEmit(true, true, true, true);
        emit CTokenSet(weth, cToken);
        vm.prank(TIMELOCK_ADDRESS);
        sut.setCToken(weth, cToken);
    }

}

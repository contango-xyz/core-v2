//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../BaseTest.sol";

contract UnderlyingPositionFactoryTest is BaseTest, IUnderlyingPositionFactoryEvents {

    using ERC20Lib for *;

    Env internal env;
    IUnderlyingPositionFactory internal sut;
    address contango;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();

        contango = address(env.contango());
        sut = env.contango().positionFactory();
    }

    function testCreateUnderlyingPosition_NEEDS_ACCOUNT() public {
        address moneyMarket = address(sut.moneyMarket(MM_AAVE));

        PositionId positionId1 = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 1000);
        PositionId positionId2 = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 1001);

        address expectedAccount1 = Clones.predictDeterministicAddress(address(moneyMarket), PositionId.unwrap(positionId1), address(sut));
        address expectedAccount2 = Clones.predictDeterministicAddress(address(moneyMarket), PositionId.unwrap(positionId2), address(sut));

        vm.expectEmit(true, true, true, true);
        emit UnderlyingPositionCreated(expectedAccount1, positionId1);
        vm.prank(contango);
        address account1 = address(sut.createUnderlyingPosition(positionId1));

        vm.expectEmit(true, true, true, true);
        emit UnderlyingPositionCreated(expectedAccount2, positionId2);
        vm.prank(contango);
        address account2 = address(sut.createUnderlyingPosition(positionId2));

        assertEq(account1, expectedAccount1, "account addresses are deterministic");
        assertEq(account2, expectedAccount2, "account addresses are deterministic");

        assertNotEq(account1, moneyMarket, "returns a new money market account");
        assertNotEq(account2, moneyMarket, "returns a new money market account");

        assertEq(
            ImmutableBeaconProxy(payable(account1)).__beacon().implementation(),
            ImmutableBeaconProxy(payable(moneyMarket)).__beacon().implementation(),
            "account points to the money market"
        );
        assertEq(
            ImmutableBeaconProxy(payable(account2)).__beacon().implementation(),
            ImmutableBeaconProxy(payable(moneyMarket)).__beacon().implementation(),
            "account points to the money market"
        );

        assertEq(address(sut.moneyMarket(positionId1)), account1, "computes the money market account");
        assertEq(address(sut.moneyMarket(positionId2)), account2, "computes the money market account");
    }

    function testPermissions(address rando) public {
        vm.assume(rando != TIMELOCK_ADDRESS && rando != contango);

        expectAccessControl(rando, "");
        sut.registerMoneyMarket(IMoneyMarket(address(0)));

        PositionId positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 1000);
        expectAccessControl(rando, CONTANGO_ROLE);
        sut.createUnderlyingPosition(positionId);
    }

    function testSetters() public {
        address compound = address(0xc0);
        vm.mockCall(compound, abi.encodeWithSelector(IMoneyMarket.moneyMarketId.selector), abi.encode(MM_COMPOUND));
        vm.mockCall(compound, abi.encodeWithSelector(IMoneyMarket.NEEDS_ACCOUNT.selector), abi.encode(true));

        vm.expectEmit(true, true, true, true);
        emit MoneyMarketRegistered(MM_COMPOUND, IMoneyMarket(compound));
        vm.prank(TIMELOCK_ADDRESS);
        sut.registerMoneyMarket(IMoneyMarket(compound));
    }

    function testValidations() public {
        address compound = address(0xc0);
        vm.mockCall(compound, abi.encodeWithSelector(IMoneyMarket.moneyMarketId.selector), abi.encode(MM_COMPOUND));
        vm.mockCall(compound, abi.encodeWithSelector(IMoneyMarket.NEEDS_ACCOUNT.selector), abi.encode(true));

        // can't register money market twice
        vm.startPrank(TIMELOCK_ADDRESS);
        sut.registerMoneyMarket(IMoneyMarket(compound));

        vm.expectRevert(
            abi.encodeWithSelector(UnderlyingPositionFactory.MoneyMarketAlreadyRegistered.selector, MM_COMPOUND, IMoneyMarket(compound))
        );
        sut.registerMoneyMarket(IMoneyMarket(compound));
        vm.stopPrank();
    }

}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import "../TestSetup.t.sol";

import "src/periphery/LastOwnerBugFix.sol";

abstract contract LastOwnerBugFixTest is Test {

    Contango contango = Contango(address(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E));

    function testFix() public virtual;

}

contract LastOwnerBugFixMainnetTest is LastOwnerBugFixTest {

    LastOwnerBugFixMainnet sut;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_688_902);

        sut = LastOwnerBugFixMainnet(address(0xb9413833d82Ddd1415243c4Ea624E0807d598f65));
    }

    function testFix() public override {
        sut.fixLastOwnerOnMigratedPositions();
        assertTrue(sut.executed(), "not executed");

        assertEq(
            contango.lastOwner(PositionId.wrap(0x7355534465444149000000000000000008ffffffff0000000012000000000055)),
            address(0xA8DDc541d443d29D61375A3E4E190Ac81fB88608)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x7355534465444149000000000000000008ffffffff0000000014000000000052)),
            address(0x3D066684D6795109CAB9606631b15C1FfaC36596)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x7773744554485745544800000000000008ffffffff0000000001000000000020)),
            address(0x499B48D5998589A4D58182De765443662BD67B77)
        );
    }

}

contract LastOwnerBugFixArbitrumTest is LastOwnerBugFixTest {

    LastOwnerBugFixArbitrum sut;

    function setUp() public {
        vm.createSelectFork("arbitrum", 202_581_888);

        sut = LastOwnerBugFixArbitrum(address(0x7d1cCB2f5Cfba8B2f653dCff1C08C1007dcE1Da9));
    }

    function testFix() public override {
        sut.fixLastOwnerOnMigratedPositions();
        assertTrue(sut.executed(), "not executed");

        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000a17)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000010ffffffff000000000000000000059f)),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x574554485553444300000000000000000effffffff0000000001000000000bf1)),
            address(0xB0F0bba5f8Daaa46185e2B476e4f42be853E710a)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000058f)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000010ffffffff0000000000000000000590)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000591)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000010ffffffff0000000000000000000592)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x574554485553444300000000000000000cffffffff00000000000000000003ef)),
            address(0x81FaCe447BF931eB0C7d1e9fFd6C7407cd2aE5a6)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000059e)),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000917)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000976)),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000062d)),
            address(0xe36B5c386Bf1a5580AB330C8c51832d3dc22e547)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000001ffffffff02000000000000000004d0)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000010ffffffff0000000000000000000575)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x415242555344430000000000000000000cffffffff0000000000000000000588)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000001ffffffff020000000000000000058a)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000010ffffffff000000000000000000058b)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000001ffffffff020000000000000000058c)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        assertEq(
            contango.lastOwner(PositionId.wrap(0x4152425553444300000000000000000010ffffffff000000000000000000058d)),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
    }

}

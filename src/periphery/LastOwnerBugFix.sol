//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../interfaces/IContango.sol";

error WrongChain();

contract LastOwnerBugFixMainnet {

    bool public executed;

    IContango public immutable contango;

    constructor(IContango _contango) {
        if (block.chainid != 1) revert WrongChain();
        contango = _contango;
    }

    function fixLastOwnerOnMigratedPositions() public {
        if (executed) return;
        contango.donatePosition(
            PositionId.wrap(0x7355534465444149000000000000000008ffffffff0000000012000000000055),
            address(0xA8DDc541d443d29D61375A3E4E190Ac81fB88608)
        );
        contango.donatePosition(
            PositionId.wrap(0x7355534465444149000000000000000008ffffffff0000000014000000000052),
            address(0x3D066684D6795109CAB9606631b15C1FfaC36596)
        );
        contango.donatePosition(
            PositionId.wrap(0x7773744554485745544800000000000008ffffffff0000000001000000000020),
            address(0x499B48D5998589A4D58182De765443662BD67B77)
        );
        executed = true;
    }

}

contract LastOwnerBugFixArbitrum {

    bool public executed;

    IContango public immutable contango;

    constructor(IContango _contango) {
        if (block.chainid != 42_161) revert WrongChain();
        contango = _contango;
    }

    function fixLastOwnerOnMigratedPositions() public {
        if (executed) return;
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000a17),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000010ffffffff000000000000000000059f),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        contango.donatePosition(
            PositionId.wrap(0x574554485553444300000000000000000effffffff0000000001000000000bf1),
            address(0xB0F0bba5f8Daaa46185e2B476e4f42be853E710a)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000058f),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000010ffffffff0000000000000000000590),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000591),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000010ffffffff0000000000000000000592),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x574554485553444300000000000000000cffffffff00000000000000000003ef),
            address(0x81FaCe447BF931eB0C7d1e9fFd6C7407cd2aE5a6)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000059e),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000917),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff0000000000000000000976),
            address(0xdE93954Cc528Ef541b261512284C844c8e0d3300)
        );
        contango.donatePosition(
            PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000062d),
            address(0xe36B5c386Bf1a5580AB330C8c51832d3dc22e547)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000001ffffffff02000000000000000004d0),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000010ffffffff0000000000000000000575),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x415242555344430000000000000000000cffffffff0000000000000000000588),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000001ffffffff020000000000000000058a),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000010ffffffff000000000000000000058b),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000001ffffffff020000000000000000058c),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        contango.donatePosition(
            PositionId.wrap(0x4152425553444300000000000000000010ffffffff000000000000000000058d),
            address(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d)
        );
        executed = true;
    }

}

// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

interface IDSToken {

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed guy, uint256 wad);
    event LogNote(bytes4 indexed sig, address indexed guy, bytes32 indexed foo, bytes32 indexed bar, uint256 wad, bytes fax) anonymous;
    event LogSetAuthority(address indexed authority);
    event LogSetOwner(address indexed owner);
    event Mint(address indexed guy, uint256 wad);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function allowance(address src, address guy) external view returns (uint256);
    function approve(address guy, uint256 wad) external returns (bool);
    function approve(address guy) external returns (bool);
    function authority() external view returns (address);
    function balanceOf(address src) external view returns (uint256);
    function burn(uint256 wad) external;
    function burn(address guy, uint256 wad) external;
    function decimals() external view returns (uint256);
    function mint(address guy, uint256 wad) external;
    function mint(uint256 wad) external;
    function move(address src, address dst, uint256 wad) external;
    function name() external view returns (bytes32);
    function owner() external view returns (address);
    function pull(address src, uint256 wad) external;
    function push(address dst, uint256 wad) external;
    function setAuthority(address authority_) external;
    function setName(bytes32 name_) external;
    function setOwner(address owner_) external;
    function start() external;
    function stop() external;
    function stopped() external view returns (bool);
    function symbol() external view returns (bytes32);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 wad) external returns (bool);
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);

}

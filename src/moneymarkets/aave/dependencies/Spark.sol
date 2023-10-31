//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ISDAI is IERC4626 {

    function pot() external view returns (IPot);

}

interface IDssPsm {

    event BuyGem(address indexed owner, uint256 value, uint256 fee);
    event SellGem(address indexed owner, uint256 value, uint256 fee);

    function buyGem(address usr, uint256 gemAmt) external;
    function sellGem(address usr, uint256 gemAmt) external;
    function gemJoin() external view returns (address);

}

interface IPot {

    function chi() external view returns (uint256);
    function rho() external view returns (uint256);
    function dsr() external view returns (uint256);
    function drip() external returns (uint256);
    function join(uint256) external;
    function exit(uint256) external;

}

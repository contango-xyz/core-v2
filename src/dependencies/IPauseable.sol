// SPDX-License-Identifier: unlicenced
pragma solidity ^0.8.4;

interface IPauseable {

    function paused() external view returns (bool);

}

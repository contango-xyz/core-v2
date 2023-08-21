//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IOracle {

    function rate(IERC20 base, IERC20 quote) external view returns (uint256);

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ISolidlyPool {

    error BelowMinimumK();
    error DepositsNotEqual();
    error FactoryAlreadySet();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InsufficientLiquidityBurned();
    error InsufficientLiquidityMinted();
    error InsufficientOutputAmount();
    error InvalidTo();
    error IsPaused();
    error K();
    error NotEmergencyCouncil();
    error StringTooLong(string str);

    function getAmountOut(uint256 amountIn, IERC20 tokenIn) external view returns (uint256);

}

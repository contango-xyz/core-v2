//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../libraries/ERC20Lib.sol";

struct Swap {
    address router;
    address spender;
    uint256 swapAmount;
    bytes swapBytes;
}

contract SimpleSpotExecutor {

    event SwapExecuted(address indexed tokenToSell, address indexed tokenToBuy, uint256 amountIn, uint256 amountOut);

    function executeSwap(IERC20 tokenToSell, IERC20 tokenToBuy, Swap calldata swap, address to) external returns (uint256 output) {
        SafeERC20.forceApprove(tokenToSell, swap.spender, swap.swapAmount);
        Address.functionCall(swap.router, swap.swapBytes);

        output = ERC20Lib.transferBalance(tokenToBuy, to);
        emit SwapExecuted(address(tokenToSell), address(tokenToBuy), swap.swapAmount, output);
    }

}

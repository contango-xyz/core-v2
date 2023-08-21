//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../dependencies/IWETH9.sol";

library ERC20Lib {

    using SafeERC20 for IERC20;
    using SafeCast for *;

    error ZeroPayer();
    error ZeroDestination();

    function transferOut(IERC20 token, address payer, address to, uint256 amount) internal returns (uint256) {
        if (payer == address(0)) revert ZeroPayer();
        if (to == address(0)) revert ZeroDestination();
        if (payer == to || amount == 0) return amount;

        return _transferOut(token, payer, to, amount);
    }

    function transferOut(IERC20 token, address payer, address to, uint256 amount, IWETH9 nativeToken) internal returns (uint256) {
        if (payer == address(0)) revert ZeroPayer();
        if (to == address(0)) revert ZeroDestination();
        if (payer == to || amount == 0) return amount;

        if (address(token) == address(nativeToken)) {
            if (payer == address(this)) {
                nativeToken.withdraw(amount);
                payable(to).transfer(amount);
            } else {
                nativeToken.deposit{ value: amount }();
            }
            return amount;
        }

        return _transferOut(token, payer, to, amount);
    }

    function _transferOut(IERC20 token, address payer, address to, uint256 amount) internal returns (uint256) {
        payer == address(this) ? token.safeTransfer(to, amount) : token.safeTransferFrom(payer, to, amount);
        return amount;
    }

    function transferBalance(IERC20 token, address to) internal returns (uint256) {
        return transferBalance(token, to, IWETH9(address(0)));
    }

    function transferBalance(IERC20 token, address to, IWETH9 nativeToken) internal returns (uint256) {
        uint256 balance = myBalance(token);
        return balance > 0 ? transferOut(token, address(this), to, balance, nativeToken) : 0;
    }

    function myBalance(IERC20 token) internal view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function myBalanceI(IERC20 token) internal view returns (int256) {
        return myBalance(token).toInt256();
    }

    function approveIfNecessary(IERC20 asset, address spender) internal {
        if (asset.allowance(address(this), spender) == 0) asset.forceApprove(spender, type(uint256).max);
    }

    function unit(IERC20 token) internal view returns (uint256) {
        return 10 ** token.decimals();
    }

}

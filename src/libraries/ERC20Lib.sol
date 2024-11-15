//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../dependencies/IWETH9.sol";
import { IPermit2 } from "../dependencies/Uniswap.sol";

import "./DataTypes.sol";

library ERC20Lib {

    using Address for address payable;
    using SafeERC20 for *;
    using SafeCast for *;

    bytes32 internal constant UPPER_BIT_MASK = (0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

    error ZeroPayer();
    error ZeroDestination();

    function transferOutNative(IWETH9 token, address payable to, uint256 amount) internal returns (uint256 amountTransferred) {
        if (to == address(0)) revert ZeroDestination();
        if (amount == 0) return amount;

        token.withdraw(amount);
        to.sendValue(amount);

        return amount;
    }

    function transferOut(IERC20 token, address payer, address to, uint256 amount) internal returns (uint256 amountTransferred) {
        if (payer == address(0)) revert ZeroPayer();
        if (to == address(0)) revert ZeroDestination();
        if (payer == to || amount == 0) return amount;

        return _transferOut(token, payer, to, amount);
    }

    function _transferOut(IERC20 token, address payer, address to, uint256 amount) internal returns (uint256 amountTransferred) {
        payer == address(this) ? token.safeTransfer(to, amount) : token.safeTransferFrom(payer, to, amount);
        return amount;
    }

    function transferBalance(IERC20 token, address to) internal returns (uint256 balance) {
        balance = myBalance(token);
        if (balance > 0) transferOut(token, address(this), to, balance);
    }

    function transferBalanceNative(IWETH9 token, address payable to) internal returns (uint256 balance) {
        balance = myBalance(token);
        if (balance > 0) transferOutNative(token, to, balance);
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

    function infiniteApproval(IERC20 token, address addr) internal {
        token.forceApprove(addr, type(uint256).max);
    }

    function applyPermit(IERC20 token, EIP2098Permit memory permit, address owner, address spender) internal {
        // Inspired by https://github.com/Uniswap/permit2/blob/main/src/libraries/SignatureVerification.sol
        IERC20Permit(address(token)).safePermit({
            owner: owner,
            spender: spender,
            value: permit.amount,
            deadline: permit.deadline,
            r: permit.r,
            v: uint8(uint256(permit.vs >> 255)) + 27,
            s: permit.vs & UPPER_BIT_MASK
        });
    }

    function pullFundsWithPermit2(IPermit2 permit2, IERC20 token, EIP2098Permit memory permit, uint256 amount, address owner, address to)
        internal
        returns (uint256)
    {
        permit2.permitTransferFrom({
            permit: IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({ token: address(token), amount: permit.amount }),
                nonce: uint256(keccak256(abi.encode(owner, token, permit.amount, permit.deadline))),
                deadline: permit.deadline
            }),
            transferDetails: IPermit2.SignatureTransferDetails({ to: to, requestedAmount: amount }),
            owner: owner,
            signature: abi.encodePacked(permit.r, permit.vs)
        });
        return amount;
    }

}

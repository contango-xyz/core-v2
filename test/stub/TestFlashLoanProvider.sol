//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/StdCheats.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "erc7399/IERC7399.sol";

import "src/libraries/DataTypes.sol";
import "src/libraries/ERC20Lib.sol";

contract TestFlashLoanProvider is IERC7399, StdCheats {

    using ERC20Lib for IERC20;

    uint256 public immutable FEE;

    constructor(uint256 fee) {
        FEE = fee;
    }

    function maxFlashLoan(address) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function flashFee(address, uint256 amount) public view override returns (uint256) {
        return amount * FEE / ONE_HUNDRED_PERCENT;
    }

    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    ) external override returns (bytes memory result) {
        IERC20 token = IERC20(asset);

        // cleanup before
        token.transfer(address(0xdead), token.myBalance());

        uint256 fee = flashFee(asset, amount);
        deal(asset, address(this), amount);

        token.transfer(loanReceiver, amount);
        result = callback(msg.sender, address(this), asset, amount, fee, data);

        require(token.myBalance() == amount + fee, "TestFlashLoaner: incorrect loan repayment");

        // cleanup after
        token.transfer(address(0xdead), token.myBalance());
    }

}

// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import "erc7399/IERC7399.sol";
import "src/libraries/ERC20Lib.sol";
import "forge-std/StdCheats.sol";

contract TestFLP is IERC7399, StdCheats {

    using ERC20Lib for IERC20;

    // fee in e4 (0.005e4 = 0.05%)
    uint256 public fee;

    function setFee(uint256 _fee) public returns (IERC7399) {
        fee = _fee;
        return this;
    }

    function maxFlashLoan(address /* asset */ ) external pure override returns (uint256) {
        return type(uint256).max;
    }

    function flashFee(address, /* asset */ uint256 amount) public view override returns (uint256) {
        return amount * fee / 1e4;
    }

    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    ) external override returns (bytes memory result) {
        deal(asset, address(this), amount);
        IERC20(asset).transferOut(address(this), loanReceiver, amount);
        uint256 loanFee = flashFee(asset, amount);
        result = callback(msg.sender, address(this), asset, amount, loanFee, data);

        if (IERC20(asset).balanceOf(address(this)) != (amount + loanFee)) revert("Flashloan not repaid");
    }

}

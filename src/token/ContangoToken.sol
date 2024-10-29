// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";

contract ContangoToken is ERC20, ERC20Permit, ERC20FlashMint, Ownable {

    error MaxSupplyExceeded();

    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    constructor(address owner) ERC20("Contango", "TANGO") ERC20Permit("Contango") {
        _transferOwnership(owner);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        require(totalSupply() <= MAX_SUPPLY, MaxSupplyExceeded());
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

}

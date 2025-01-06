//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../libraries/DataTypes.sol";
import "../libraries/Roles.sol";

// Permissioned slimed down version of https://github.com/mds1/multicall/blob/main/src/Multicall3.sol

struct Call {
    address target;
    uint256 value;
    bytes callData;
}

struct Result {
    bool success;
    bytes returnData;
}

contract TaxMan is AccessControl, Pausable {

    error CallFailed(uint256 index, bytes returnData);
    error NotEnoughBalance(IERC20 token, uint256 expected, uint256 actual);

    constructor(Timelock timelock) {
        // Grant the admin role to the timelock by default
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function execute(Call[] calldata calls) public payable onlyRole(BOT_ROLE) whenNotPaused returns (Result[] memory returnData) {
        uint256 length = calls.length;
        returnData = new Result[](length);
        Call calldata call;
        for (uint256 i = 0; i < length; i++) {
            Result memory result = returnData[i];
            call = calls[i];
            (result.success, result.returnData) = call.target.call{ value: call.value }(call.callData);
            require(result.success, CallFailed(i, result.returnData));
        }
    }

    function assertBalanceGreaterOrEqualThan(IERC20 token, address account, uint256 value) public view {
        uint256 balance = token.balanceOf(account);
        require(balance >= value, NotEnoughBalance(token, value, balance));
    }

    function pause() external onlyRole(EMERGENCY_BREAK_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(RESTARTER_ROLE) {
        _unpause();
    }

    receive() external payable { }

}

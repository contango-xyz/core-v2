// SPDX-License-Identifier: MIT
// Inspired by OpenZeppelin Contracts (last updated v4.9.0) (utils/Multicall.sol)

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev Provides a function to batch together multiple payable calls in a single external call.
 *
 * _Available since v4.1._
 */
abstract contract PayableMulticall {

    /**
     * @dev Receives and executes a batch of function calls on this contract.
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function multicall(bytes[] calldata data) external payable virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

}

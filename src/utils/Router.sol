//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";

/// @dev Router forwards calls between two contracts, so that any permissions
/// given to the original caller are stripped from the call.
/// This is useful when implementing generic call routing functions on contracts
/// that might have ERC20 approvals or AccessControl authorizations.

// Inspired by https://github.com/yieldprotocol/vault-v2/blob/master/src/Router.sol
contract Router {

    using Address for address;

    /// @dev Allow users to route calls, to be used with batch
    function route(address target, uint256 value, bytes calldata data) external payable returns (bytes memory result) {
        return target.functionCallWithValue(data, value);
    }

}

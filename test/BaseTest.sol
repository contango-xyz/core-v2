//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./TestSetup.t.sol";

abstract contract BaseTest is Test {

    function removeSelector(bytes memory calldataWithSelector) internal pure returns (bytes memory) {
        bytes memory calldataWithoutSelector;

        require(calldataWithSelector.length >= 4);

        assembly {
            let totalLength := mload(calldataWithSelector)
            let targetLength := sub(totalLength, 4)
            calldataWithoutSelector := mload(0x40)

            // Set the length of callDataWithoutSelector (initial length - 4)
            mstore(calldataWithoutSelector, targetLength)

            // Mark the memory space taken for callDataWithoutSelector as allocated
            mstore(0x40, add(0x20, targetLength))

            // Process first 32 bytes (we only take the last 28 bytes)
            mstore(add(calldataWithoutSelector, 0x20), shl(0x20, mload(add(calldataWithSelector, 0x20))))

            // Process all other data by chunks of 32 bytes
            for { let i := 0x1C } lt(i, targetLength) { i := add(i, 0x20) } {
                mstore(add(add(calldataWithoutSelector, 0x20), i), mload(add(add(calldataWithSelector, 0x20), add(i, 0x04))))
            }
        }

        return calldataWithoutSelector;
    }

    function expectAccessControl(address caller, bytes32 role) internal {
        vm.prank(caller);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(caller), 20),
                " is missing role ",
                Strings.toHexString(uint256(role), 32)
            )
        );
    }

    function skipWithBlock(uint256 time) internal {
        skip(time);
        vm.roll(block.number + time / 12);
    }

    function _swap(SwapRouter02 router, IERC20 from, IERC20 to, uint256 amount, address recipient)
        internal
        pure
        returns (SwapData memory)
    {
        return SwapData({
            router: address(router),
            spender: address(router),
            amountIn: amount,
            minAmountOut: 0, // UI's problem
            swapBytes: abi.encodeWithSelector(
                router.exactInput.selector,
                SwapRouter02.ExactInputParams({
                    path: abi.encodePacked(address(from), uint24(500), address(to)),
                    recipient: recipient,
                    amountIn: amount,
                    amountOutMinimum: 0 // UI's problem
                 })
            )
        });
    }

}

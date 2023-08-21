// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/**
 * @custom:proxied
 * @custom:predeploy 0x420000000000000000000000000000000000000F
 * @title GasPriceOracle
 * @notice This contract maintains the variables responsible for computing the L1 portion of the
 *         total fee charged on L2. Before Bedrock, this contract held variables in state that were
 *         read during the state transition function to compute the L1 portion of the transaction
 *         fee. After Bedrock, this contract now simply proxies the L1Block contract, which has
 *         the values used to compute the L1 portion of the fee in its state.
 */
interface GasPriceOracle {

    /**
     * @notice Computes the L1 portion of the fee based on the size of the rlp encoded input
     *         transaction, the current L1 base fee, and the various dynamic parameters.
     *
     * @param data Unsigned fully RLP-encoded transaction to get the L1 fee for.
     *
     * @return L1 fee that should be paid for the tx
     */
    function getL1Fee(bytes memory data) external view returns (uint256);

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../dependencies/GasPriceOracle.sol";
import "./OrderManager.sol";

contract OrderManagerOptimism is OrderManager {

    GasPriceOracle public constant PRICE_ORACLE = GasPriceOracle(0x420000000000000000000000000000000000000F);

    constructor(IContango _contango, address _treasury) OrderManager(_contango, _treasury) { }

    function _gasCost() internal view override returns (uint256 gasCost) {
        // solhint-disable-next-line avoid-tx-origin
        uint256 l1GasCost = PRICE_ORACLE.getL1Fee(abi.encodePacked(bytes1(0x02), tx.origin, address(this), msg.data));

        // 21000 min tx gas (starting gasStart value) + gas used so far + 60k for the 2 ERC20 transfers
        uint256 l2GasSpent = gasStart - gasleft() + TWO_ERC20_TRANSFERS_GAS_ESTIMATE;
        // We use (block.basefee + gasTip) to cap how much tip we are willing to pay, it's effectively a max-fee-per-gas
        uint256 l2GasCost = l2GasSpent * (block.basefee + gasTip);

        gasCost = l1GasCost + l2GasCost;
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../dependencies/ArbGasInfo.sol";
import "./OrderManager.sol";

contract OrderManagerArbitrum is OrderManager {

    ArbGasInfo public constant GAS_INFO = ArbGasInfo(0x000000000000000000000000000000000000006C);

    constructor(IContango _contango, address _treasury) OrderManager(_contango, _treasury) { }

    function _gasCost() internal view override returns (uint256 gasCost) {
        (,,,,, uint256 totalGasPrice) = GAS_INFO.getPricesInWei();
        uint256 l1GasCost = GAS_INFO.getCurrentTxL1GasFees();

        // 21000 min tx gas (starting gasStart value) + gas used so far + 60k for the 2 ERC20 transfers
        uint256 gasSpent = gasStart - gasleft() + TWO_ERC20_TRANSFERS_GAS_ESTIMATE;

        uint256 l2GasCost = gasSpent * totalGasPrice;

        gasCost = l2GasCost + l1GasCost;
    }

}

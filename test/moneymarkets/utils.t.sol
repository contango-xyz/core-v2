// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import { AvailableActions } from "src/moneymarkets/interfaces/IMoneyMarketView.sol";

function enabled(AvailableActions[] memory actions, AvailableActions action) pure returns (bool) {
    for (uint256 i; i < actions.length; i++) {
        if (actions[i] == action) return true;
    }
    return false;
}

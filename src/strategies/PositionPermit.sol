//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../libraries/DataTypes.sol";

struct PositionPermit {
    PositionId positionId;
    uint256 deadline;
    bytes32 r;
    bytes32 vs;
}

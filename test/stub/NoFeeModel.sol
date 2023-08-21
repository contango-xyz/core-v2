//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/interfaces/IFeeModel.sol";

contract NoFeeModel is IFeeModel {

    /// @inheritdoc IFeeModel
    function calculateFee(address, PositionId, uint256) external pure override returns (uint256) {
        return 0;
    }

}

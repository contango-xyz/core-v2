//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./AaveMoneyMarket.sol";

contract AaveMoneyMarketWithoutFlashBorrow is AaveMoneyMarket {

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) AaveMoneyMarket(_moneyMarketId, _contango, _pool, _dataProvider, _rewardsController) { }

    // ===== IFlashBorrowProvider =====

    // Spark has disabled this functionality
    // We revert instead of refactoring all the code hierarchy cause audits are expensive

    function flashBorrow(IERC20, uint256, bytes calldata, function(IERC20, uint256, bytes memory) external  returns (bytes memory))
        public
        pure
        override
        returns (bytes memory)
    {
        revert UnsupportedOperation();
    }

    function executeOperation(address[] calldata, uint256[] calldata, uint256[] calldata, address, bytes calldata)
        public
        pure
        override
        returns (bool)
    {
        revert UnsupportedOperation();
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId;
    }

}

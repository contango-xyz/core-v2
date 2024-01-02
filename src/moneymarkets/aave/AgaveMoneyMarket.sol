//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./dependencies/IAgaveBaseIncentivesController.sol";

import "./AaveV2MoneyMarket.sol";

contract AgaveMoneyMarket is AaveV2MoneyMarket {

    IAgaveBaseIncentivesController public immutable agaveRewardsController;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) AaveV2MoneyMarket(_moneyMarketId, _contango, _pool, _dataProvider, _rewardsController) {
        agaveRewardsController = IAgaveBaseIncentivesController(address(_rewardsController));
    }

    // ====== IMoneyMarket =======

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        IERC20[] memory tokens = toArray(_aToken(collateralAsset), _vToken(debtAsset));
        uint256 amount = agaveRewardsController.getRewardsBalance(tokens, address(this));
        agaveRewardsController.claimRewards(tokens, amount, to);
    }

}

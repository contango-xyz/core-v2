//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/IPoolV2.sol";

import "./AaveMoneyMarket.sol";

contract AaveV2MoneyMarket is AaveMoneyMarket {

    IPoolV2 public immutable poolV2;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) AaveMoneyMarket(_moneyMarketId, _contango, _pool, _dataProvider, _rewardsController) {
        poolV2 = IPoolV2(address(_pool));
    }

    // ====== IMoneyMarket =======

    function _supply(IERC20 asset, uint256 amount) internal virtual override {
        pool.deposit({ asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0 });
    }

    function _aToken(IERC20 asset) internal view virtual override returns (IERC20 aToken) {
        aToken = IERC20(poolV2.getReserveData(address(asset)).aTokenAddress);
    }

    function _vToken(IERC20 asset) internal view virtual override returns (IERC20 vToken) {
        vToken = IERC20(poolV2.getReserveData(address(asset)).variableDebtTokenAddress);
    }

}

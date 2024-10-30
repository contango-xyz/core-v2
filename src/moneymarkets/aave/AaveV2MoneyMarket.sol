//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/IPoolAddressesProviderV2.sol";

import "./AaveMoneyMarket.sol";

contract AaveV2MoneyMarket is AaveMoneyMarket {

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPoolAddressesProvider _poolAddressesProvider,
        IAaveRewardsController _rewardsController,
        bool _flashBorrowEnabled
    ) AaveMoneyMarket(_moneyMarketId, _contango, _poolAddressesProvider, _rewardsController, _flashBorrowEnabled) { }

    // ====== IMoneyMarket =======

    function _supply(IERC20 asset, uint256 amount) internal virtual override {
        poolV2().deposit({ asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0 });
    }

    function _aToken(IERC20 asset) internal view virtual override returns (IERC20 aToken) {
        aToken = IERC20(poolV2().getReserveData(address(asset)).aTokenAddress);
    }

    function _vToken(IERC20 asset) internal view virtual override returns (IERC20 vToken) {
        vToken = IERC20(poolV2().getReserveData(address(asset)).variableDebtTokenAddress);
    }

    function pool() public view override returns (IPool) {
        return IPool(address(poolV2()));
    }

    function poolV2() public view returns (IPoolV2) {
        return IPoolAddressesProviderV2(address(poolAddressesProvider)).getLendingPool();
    }

}

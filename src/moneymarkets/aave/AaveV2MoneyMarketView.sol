//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/IPoolV2.sol";
import "./dependencies/IPoolDataProviderV2.sol";
import "./dependencies/IPoolAddressesProviderV2.sol";

import "./AaveMoneyMarketView.sol";

contract AaveV2MoneyMarketView is AaveMoneyMarketView {

    uint256 public immutable oracleUnit;
    IPoolDataProviderV2 public immutable dataProviderV2;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        IPoolAddressesProvider _poolAddressesProvider,
        IPoolDataProviderV2 _dataProviderV2,
        uint256 __oracleUnit,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    )
        AaveMoneyMarketView(
            _moneyMarketId,
            _moneyMarketName,
            _contango,
            _poolAddressesProvider,
            IAaveRewardsController(address(0)),
            _nativeToken,
            _nativeUsdOracle,
            Version.V2
        )
    {
        oracleUnit = __oracleUnit;
        dataProviderV2 = _dataProviderV2;
    }

    // ====== IMoneyMarketView =======

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        (balances_.collateral,,,,,,,,) = dataProviderV2.getUserReserveData(address(collateralAsset), account);
        (,, balances_.debt,,,,,,) = dataProviderV2.getUserReserveData(address(debtAsset), account);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return oracleUnit;
    }

    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) {
        return _derivePriceInUSD(asset);
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _apy({ rate: poolV2().getReserveData(address(debtAsset)).currentVariableBorrowRate / 1e9, perSeconds: 365 days });
        lending = _apy({ rate: poolV2().getReserveData(address(collateralAsset)).currentLiquidityRate / 1e9, perSeconds: 365 days });
    }

    function collectIrmDataV2V3(IERC20 asset) public view override returns (IRMData memory data) {
        {
            (, data.totalStableDebt, data.totalVariableDebt,,,, data.averageStableBorrowRate,,,) =
                dataProviderV2.getReserveData(address(asset));
        }

        {
            (,,,, data.reserveFactor,,,,,) = dataProviderV2.getReserveConfigurationData(address(asset));
        }
        {
            (address aTokenAddress,,) = dataProviderV2.getReserveTokensAddresses(address(asset));
            data.aTokenReserveBalance = asset.balanceOf(aTokenAddress);
        }

        {
            IDefaultReserveInterestRateStrategyV2 irStrategy = poolV2().getReserveData(address(asset)).interestRateStrategyAddress;
            data.optimalUsageRatio = irStrategy.OPTIMAL_UTILIZATION_RATE();
            data.maxExcessUsageRatio = irStrategy.EXCESS_UTILIZATION_RATE();
            data.variableRateSlope1 = irStrategy.variableRateSlope1();
            data.variableRateSlope2 = irStrategy.variableRateSlope2();
            data.baseVariableBorrowRate = irStrategy.baseVariableBorrowRate();
        }
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (, ltv, liquidationThreshold,,,,,,,) = dataProvider().getReserveConfigurationData(address(collateralAsset));

        ltv *= 1e14;
        liquidationThreshold *= 1e14;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _borrowingLiquidity(debtAsset);
        lending = _lendingLiquidity(collateralAsset);
    }

    function _borrowingLiquidity(IERC20 asset) internal view virtual override returns (uint256 borrowingLiquidity_) {
        IPoolV2.ReserveData memory reserve = poolV2().getReserveData(address(asset));
        borrowingLiquidity_ = asset.balanceOf(reserve.aTokenAddress);
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual override returns (uint256 lendingLiquidity_) {
        lendingLiquidity_ = asset.totalSupply();
    }

    function _reserveStatus(IERC20 asset, bool borrowing)
        internal
        view
        virtual
        override
        returns (bool isActive, bool isFrozen, bool isPaused, bool enabled)
    {
        bool usageAsCollateralEnabled;
        bool borrowingEnabled;
        (,,,,, usageAsCollateralEnabled, borrowingEnabled,, isActive, isFrozen) = dataProvider().getReserveConfigurationData(address(asset));
        enabled = borrowing ? borrowingEnabled : usageAsCollateralEnabled;

        isPaused = poolV2().paused();
    }

    function _getTokenSupply(IERC20 asset, bool borrowing) internal view override returns (uint256 tokenSupply) {
        (uint256 availableLiquidity,, uint256 totalVariableDebt,,,,,,,) = dataProviderV2.getReserveData(address(asset));
        tokenSupply = borrowing ? totalVariableDebt : availableLiquidity + totalVariableDebt;
    }

    function pool() public view override returns (IPool) {
        return IPool(address(poolV2()));
    }

    function poolV2() public view returns (IPoolV2) {
        return IPoolAddressesProviderV2(address(poolAddressesProvider)).getLendingPool();
    }

    function dataProvider() public view override returns (IPoolDataProviderV3) {
        return IPoolDataProviderV3(address(dataProviderV2));
    }

}

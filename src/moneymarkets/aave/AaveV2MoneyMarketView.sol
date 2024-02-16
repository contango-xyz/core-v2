//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./dependencies/IPoolV2.sol";
import "./dependencies/IPoolDataProviderV2.sol";

import "./AaveMoneyMarketView.sol";

contract AaveV2MoneyMarketView is AaveMoneyMarketView {

    IPoolV2 public immutable poolV2;
    IPoolDataProviderV2 public immutable dataProviderV2;
    uint256 public immutable oracleUnit;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveOracle _oracle,
        uint256 __oracleUnit,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) AaveMoneyMarketView(_moneyMarketId, _moneyMarketName, _contango, _pool, _dataProvider, _oracle, _nativeToken, _nativeUsdOracle) {
        poolV2 = IPoolV2(address(_pool));
        dataProviderV2 = IPoolDataProviderV2(address(_dataProvider));
        oracleUnit = __oracleUnit;
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

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = poolV2.getReserveData(address(debtAsset)).currentVariableBorrowRate / 1e9;
        lending = poolV2.getReserveData(address(collateralAsset)).currentLiquidityRate / 1e9;
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (, ltv, liquidationThreshold,,,,,,,) = dataProvider.getReserveConfigurationData(address(collateralAsset));

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
        IPoolV2.ReserveData memory reserve = poolV2.getReserveData(address(asset));
        borrowingLiquidity_ = asset.balanceOf(reserve.aTokenAddress);
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual override returns (uint256 lendingLiquidity_) {
        (,,,,, bool usageAsCollateralEnabled,,,,) = dataProvider.getReserveConfigurationData(address(asset));
        if (!usageAsCollateralEnabled) return 0;

        lendingLiquidity_ = asset.totalSupply();
    }

}

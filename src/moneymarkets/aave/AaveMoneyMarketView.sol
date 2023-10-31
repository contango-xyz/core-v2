//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";

import "../interfaces/IMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";
import "../../libraries/Arrays.sol";

contract AaveMoneyMarketView is IMoneyMarketView {

    error OracleBaseCurrencyNotUSD();

    using Math for *;

    MoneyMarketId public immutable override moneyMarketId;
    IUnderlyingPositionFactory public immutable positionFactory;
    IPoolAddressesProvider public immutable provider;
    IPool public immutable pool;

    constructor(MoneyMarketId _moneyMarketId, IPoolAddressesProvider _provider, IUnderlyingPositionFactory _positionFactory) {
        moneyMarketId = _moneyMarketId;
        provider = _provider;
        pool = IPool(_provider.getPool());
        positionFactory = _positionFactory;
    }

    // ====== IMoneyMarketView =======

    function balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        (balances_.collateral,,,,,,,,) = _dataProvider().getUserReserveData(address(collateralAsset), account);
        (,, balances_.debt,,,,,,) = _dataProvider().getUserReserveData(address(debtAsset), account);
    }

    function prices(PositionId, IERC20 collateralAsset, IERC20 debtAsset) public view virtual override returns (Prices memory prices_) {
        IAaveOracle oracle = IAaveOracle(provider.getPriceOracle());
        uint256[] memory pricesArr = oracle.getAssetsPrices(toArray(address(collateralAsset), address(debtAsset)));

        prices_.collateral = pricesArr[0];
        prices_.debt = pricesArr[1];
        prices_.unit = oracle.BASE_CURRENCY_UNIT();
    }

    function thresholds(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        uint256 eModeCategory =
            positionId.getNumber() > 0 ? pool.getUserEMode(_account(positionId)) : _eModeCategory(collateralAsset, debtAsset);

        if (eModeCategory > 0) {
            DataTypes.EModeCategory memory eModeCategoryData = pool.getEModeCategoryData(uint8(eModeCategory));
            ltv = eModeCategoryData.ltv;
            liquidationThreshold = eModeCategoryData.liquidationThreshold;
        } else {
            (, ltv, liquidationThreshold,,,,,,,) = _dataProvider().getReserveConfigurationData(address(collateralAsset));
        }

        ltv *= 1e14;
        liquidationThreshold *= 1e14;
    }

    function liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _borrowingLiquidity(debtAsset);
        lending = _lendingLiquidity(collateralAsset);

        uint256 debtCeiling = _dataProvider().getDebtCeiling(address(collateralAsset));
        if (debtCeiling > 0) {
            IAaveOracle oracle = IAaveOracle(provider.getPriceOracle());
            if (oracle.BASE_CURRENCY() != address(0)) revert OracleBaseCurrencyNotUSD();
            uint256 debtAssetPrice = oracle.getAssetPrice(address(debtAsset));

            uint256 available = (debtCeiling - pool.getReserveData(address(collateralAsset)).isolationModeTotalDebt)
                * (oracle.BASE_CURRENCY_UNIT() / (10 ** _dataProvider().getDebtCeilingDecimals()));

            borrowing = Math.min(borrowing, available * 10 ** debtAsset.decimals() / debtAssetPrice);
        }
    }

    function rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset) public view virtual returns (uint256 borrowing, uint256 lending) {
        borrowing = pool.getReserveData(address(debtAsset)).currentVariableBorrowRate / 1e9;
        lending = pool.getReserveData(address(collateralAsset)).currentLiquidityRate / 1e9;
    }

    // ===== Internal Helper Functions =====

    function _borrowingLiquidity(IERC20 asset) internal view returns (uint256 borrowingLiquidity_) {
        (uint256 borrowCap,) = _dataProvider().getReserveCaps(address(asset));
        borrowCap = borrowCap * 10 ** asset.decimals();
        uint256 totalDebt = _dataProvider().getTotalDebt(address(asset));

        uint256 maxBorrowable = borrowCap > totalDebt ? borrowCap - totalDebt : 0;
        (address aTokenAddress,,) = _dataProvider().getReserveTokensAddresses(address(asset));
        uint256 available = asset.balanceOf(aTokenAddress);

        borrowingLiquidity_ = borrowCap == 0 ? available : Math.min(maxBorrowable, available);
    }

    function _lendingLiquidity(IERC20 asset) internal view returns (uint256 lendingLiquidity_) {
        (uint256 decimals,,,,, bool usageAsCollateralEnabled,,,,) = _dataProvider().getReserveConfigurationData(address(asset));
        if (!usageAsCollateralEnabled) return 0;

        (, uint256 supplyCap) = _dataProvider().getReserveCaps(address(asset));
        if (supplyCap == 0) return type(uint256).max; // Infinite supply cap

        supplyCap = supplyCap * 10 ** decimals;
        uint256 currentSupply = _dataProvider().getATokenTotalSupply(address(asset));

        lendingLiquidity_ = supplyCap > currentSupply ? supplyCap - currentSupply : 0;
    }

    function _eModeCategory(IERC20 collateralAsset, IERC20 debtAsset) internal view returns (uint256 eModeCategory) {
        uint256 collateralEModeCategory = _dataProvider().getReserveEModeCategory(address(collateralAsset));
        if (collateralEModeCategory > 0 && collateralEModeCategory == _dataProvider().getReserveEModeCategory(address(debtAsset))) {
            eModeCategory = collateralEModeCategory;
        }
    }

    function _account(PositionId positionId) internal view returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

    function _dataProvider() internal view returns (IPoolDataProvider) {
        return IPoolDataProvider(provider.getPoolDataProvider());
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "./dependencies/IAuditor.sol";
import "./ExactlyReverseLookup.sol";

import "../interfaces/IMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";

contract ExactlyMoneyMarketView is IMoneyMarketView {

    using ERC20Lib for IERC20;
    using Math for uint256;

    MoneyMarket public immutable moneyMarketId;
    ExactlyReverseLookup public immutable reverseLookup;
    IAuditor public immutable auditor;
    IUnderlyingPositionFactory public immutable positionFactory;

    constructor(
        MoneyMarket _moneyMarketId,
        ExactlyReverseLookup _reverseLookup,
        IAuditor _auditor,
        IUnderlyingPositionFactory _positionFactory
    ) {
        moneyMarketId = _moneyMarketId;
        reverseLookup = _reverseLookup;
        auditor = _auditor;
        positionFactory = _positionFactory;
    }

    function balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) public view returns (Balances memory balances_) {
        IMarket collateralMarket = reverseLookup.markets(collateralAsset);
        balances_.collateral = collateralMarket.convertToAssets(collateralMarket.balanceOf(_account(positionId)));
        balances_.debt = reverseLookup.markets(debtAsset).previewDebt(_account(positionId));
    }

    function normalisedBalances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        external
        view
        returns (NormalisedBalances memory normalisedBalances_)
    {
        Prices memory prices_ = prices(Symbol.wrap(""), collateralAsset, debtAsset);
        Balances memory balances_ = balances(positionId, collateralAsset, debtAsset);
        normalisedBalances_.collateral =
            balances_.collateral.mulDiv(prices_.collateral, 10 ** collateralAsset.decimals(), Math.Rounding.Down);
        normalisedBalances_.debt = balances_.debt.mulDiv(prices_.debt, 10 ** debtAsset.decimals(), Math.Rounding.Up);
        normalisedBalances_.unit = prices_.unit;
    }

    function prices(Symbol, IERC20 collateralAsset, IERC20 debtAsset) public view returns (Prices memory prices_) {
        (,,,, address collateralPriceFeed) = auditor.markets(reverseLookup.markets(collateralAsset));
        (,,,, address debtPriceFeed) = auditor.markets(reverseLookup.markets(debtAsset));
        prices_.collateral = auditor.assetPrice(collateralPriceFeed);
        prices_.debt = auditor.assetPrice(debtPriceFeed);
        prices_.unit = WAD;
    }

    function borrowingLiquidity(IERC20 asset) external view returns (uint256 liquidity) {
        IMarket market = reverseLookup.markets(asset);
        uint256 adjusted = market.floatingAssets().mulDiv(WAD - market.reserveFactor(), WAD, Math.Rounding.Down);
        uint256 borrowed = market.floatingBackupBorrowed() + market.totalFloatingBorrowAssets();
        liquidity = adjusted > borrowed ? adjusted - borrowed : 0;
    }

    function lendingLiquidity(IERC20 token) external view returns (uint256) {
        return token.totalSupply();
    }

    function minCR(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) public view returns (uint256) {
        (, uint256 liquidationThreshold) = thresholds(positionId, collateralAsset, debtAsset);
        return WAD.mulDiv(WAD, liquidationThreshold, Math.Rounding.Up);
    }

    function thresholds(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (uint256 collateralAdjustFactor,,,,) = auditor.markets(reverseLookup.markets(collateralAsset));
        (uint256 debtAdjustFactor,,,,) = auditor.markets(reverseLookup.markets(debtAsset));

        liquidationThreshold = collateralAdjustFactor.mulDiv(debtAdjustFactor, WAD, Math.Rounding.Down);
        ltv = liquidationThreshold;
    }

    function borrowingRate(IERC20 asset) external view returns (uint256 borrowingRate_) { }

    function lendingRate(IERC20 asset) external view returns (uint256 lendingRate_) { }

    function _account(PositionId positionId) internal view returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

}

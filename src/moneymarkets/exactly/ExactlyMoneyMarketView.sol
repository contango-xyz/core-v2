//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "./dependencies/IAuditor.sol";
import "./dependencies/IInterestRateModel.sol";
import "./ExactlyReverseLookup.sol";

import "../interfaces/IMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";

contract ExactlyMoneyMarketView is IMoneyMarketView {

    using ERC20Lib for IERC20;
    using Math for uint256;

    MoneyMarketId public immutable moneyMarketId;
    ExactlyReverseLookup public immutable reverseLookup;
    IAuditor public immutable auditor;
    IUnderlyingPositionFactory public immutable positionFactory;

    constructor(
        MoneyMarketId _moneyMarketId,
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
        IMarket collateralMarket = reverseLookup.market(collateralAsset);
        balances_.collateral = collateralMarket.convertToAssets(collateralMarket.balanceOf(_account(positionId)));
        balances_.debt = reverseLookup.market(debtAsset).previewDebt(_account(positionId));
    }

    function prices(PositionId, IERC20 collateralAsset, IERC20 debtAsset) public view returns (Prices memory prices_) {
        (,,,, address collateralPriceFeed) = auditor.markets(reverseLookup.market(collateralAsset));
        (,,,, address debtPriceFeed) = auditor.markets(reverseLookup.market(debtAsset));
        prices_.collateral = auditor.assetPrice(collateralPriceFeed);
        prices_.debt = auditor.assetPrice(debtPriceFeed);
        prices_.unit = WAD;
    }

    function thresholds(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (uint256 collateralAdjustFactor,,,,) = auditor.markets(reverseLookup.market(collateralAsset));
        (uint256 debtAdjustFactor,,,,) = auditor.markets(reverseLookup.market(debtAsset));

        liquidationThreshold = collateralAdjustFactor.mulDiv(debtAdjustFactor, WAD, Math.Rounding.Down);
        ltv = liquidationThreshold;
    }

    function liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset) external view returns (uint256 borrowing, uint256 lending) {
        IMarket market = reverseLookup.market(debtAsset);
        uint256 adjusted = market.floatingAssets().mulDiv(WAD - market.reserveFactor(), WAD, Math.Rounding.Down);
        uint256 borrowed = market.floatingBackupBorrowed() + market.totalFloatingBorrowAssets();
        borrowing = adjusted > borrowed ? adjusted - borrowed : 0;

        lending = collateralAsset.totalSupply();
    }

    function rates(PositionId, IERC20, IERC20 debtAsset) external view returns (uint256 borrowing, uint256 lending) {
        lending = 0;

        IMarket market = reverseLookup.market(debtAsset);
        borrowing = market.interestRateModel().floatingRate(
            market.floatingAssets() > 0 ? Math.min(market.floatingDebt().mulDiv(1e18, market.floatingAssets(), Math.Rounding.Up), 1e18) : 0
        );
    }

    function _account(PositionId positionId) internal view returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

}

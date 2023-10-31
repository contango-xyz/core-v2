//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "../interfaces/IMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";

import "./dependencies/IComptroller.sol";
import "./dependencies/IChainlinkPriceOracle.sol";

contract SonneMoneyMarketView is IMoneyMarketView {

    using ERC20Lib for IERC20;
    using Math for uint256;

    MoneyMarketId public immutable moneyMarketId;
    IUnderlyingPositionFactory public immutable positionFactory;
    IComptroller public immutable comptroller;
    IWETH9 public immutable nativeToken;

    constructor(MoneyMarketId _moneyMarketId, IUnderlyingPositionFactory _positionFactory, IComptroller _comptroller, IWETH9 _nativeToken) {
        moneyMarketId = _moneyMarketId;
        positionFactory = _positionFactory;
        comptroller = _comptroller;
        nativeToken = _nativeToken;
    }

    function balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) public returns (Balances memory balances_) {
        address account = _account(positionId);
        balances_.collateral = cToken(collateralAsset).balanceOfUnderlying(account);
        balances_.debt = cToken(debtAsset).borrowBalanceCurrent(account);
    }

    function prices(PositionId, IERC20 collateralAsset, IERC20 debtAsset) public view returns (Prices memory prices_) {
        IChainlinkPriceOracle oracle = IChainlinkPriceOracle(comptroller.oracle());
        prices_.collateral = oracle.getPrice(address(cToken(collateralAsset)));
        prices_.debt = oracle.getPrice(address(cToken(debtAsset)));
        prices_.unit = 1e18;
    }

    function thresholds(PositionId, IERC20 collateralAsset, IERC20 /* debtAsset */ )
        public
        view
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (, ltv,) = comptroller.markets(address(cToken(collateralAsset)));
        liquidationThreshold = ltv;
    }

    function liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset) external view returns (uint256 borrowing, uint256 lending) {
        borrowing = debtAsset.balanceOf(address(cToken(debtAsset))) * 0.95e18 / 1e18;
        lending = collateralAsset.totalSupply();
    }

    function rates(PositionId, IERC20, IERC20) external pure returns (uint256, uint256) {
        // solhint-disable-next-line custom-errors
        revert("Not implemented");
    }

    function _account(PositionId positionId) internal view returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

    function cToken(IERC20 asset) public view returns (ICToken cToken_) {
        address[] memory allMarkets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < allMarkets.length; i++) {
            cToken_ = ICToken(allMarkets[i]);
            if (cToken_.underlying() == address(asset)) return cToken_;
        }
        // solhint-disable-next-line custom-errors
        revert("UnsupportedAsset");
    }

}

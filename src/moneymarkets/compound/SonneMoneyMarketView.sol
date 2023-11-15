//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./CompoundMoneyMarketView.sol";
import "./dependencies/IChainlinkPriceOracle.sol";

contract SonneMoneyMarketView is CompoundMoneyMarketView {

    constructor(MoneyMarketId _moneyMarketId, IUnderlyingPositionFactory _positionFactory, CompoundReverseLookup _reverseLookup)
        CompoundMoneyMarketView(_moneyMarketId, _positionFactory, _reverseLookup)
    { }

    function prices(PositionId, IERC20 collateralAsset, IERC20 debtAsset) public view override returns (Prices memory prices_) {
        IChainlinkPriceOracle oracle = IChainlinkPriceOracle(comptroller.oracle());
        prices_.collateral = oracle.getPrice(address(cToken(collateralAsset)));
        prices_.debt = oracle.getPrice(address(cToken(debtAsset)));
        prices_.unit = 1e18;
    }

}

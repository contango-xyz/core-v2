//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/IAuditor.sol";

interface ExactlyReverseLookupEvents {

    event MarketSet(IERC20 indexed asset, IExactlyMarket indexed market);

}

contract ExactlyReverseLookup is ExactlyReverseLookupEvents {

    error MarketNotFound(IERC20 asset);
    error MarketNotListed(IExactlyMarket market);

    IAuditor public immutable auditor;

    mapping(IERC20 token => IExactlyMarket market) public markets;
    mapping(IExactlyMarket market => IERC20 token) public assets;

    constructor(IAuditor _auditor) {
        auditor = _auditor;
    }

    function setMarket(IExactlyMarket _market) external {
        require(auditor.markets(_market).isListed, MarketNotListed(_market));
        IERC20 asset = _market.asset();

        markets[asset] = _market;
        assets[_market] = asset;
        emit MarketSet(asset, _market);
    }

    function market(IERC20 asset) external view returns (IExactlyMarket _market) {
        _market = markets[asset];
        if (_market == IExactlyMarket(address(0))) revert MarketNotFound(asset);
    }

}

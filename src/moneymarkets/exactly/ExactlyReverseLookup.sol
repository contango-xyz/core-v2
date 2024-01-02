//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "../../libraries/DataTypes.sol";
import "./dependencies/IAuditor.sol";

interface ExactlyReverseLookupEvents {

    event MarketSet(IERC20 indexed asset, IExactlyMarket indexed market);

}

contract ExactlyReverseLookup is ExactlyReverseLookupEvents, AccessControl {

    error MarketNotFound(IERC20 asset);

    IAuditor public immutable auditor;

    mapping(IERC20 token => IExactlyMarket market) private _markets;

    constructor(Timelock timelock, IAuditor _auditor) {
        auditor = _auditor;
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _update(_auditor);
    }

    function update() external {
        _update(auditor);
    }

    function _update(IAuditor _auditor) private {
        if (address(_auditor) != address(0)) {
            IExactlyMarket[] memory allMarkets = _auditor.allMarkets();
            for (uint256 i = 0; i < allMarkets.length; i++) {
                IExactlyMarket _market = allMarkets[i];
                _markets[_market.asset()] = _market;
                emit MarketSet(_market.asset(), _market);
            }
        }
    }

    function setMarket(IERC20 asset, IExactlyMarket _market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _markets[asset] = _market;
        emit MarketSet(asset, _market);
    }

    function market(IERC20 asset) external view returns (IExactlyMarket _market) {
        _market = _markets[asset];
        if (_market == IExactlyMarket(address(0))) revert MarketNotFound(asset);
    }

}

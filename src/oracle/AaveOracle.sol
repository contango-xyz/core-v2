//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";

import "../libraries/Arrays.sol";
import "../interfaces/IOracle.sol";

contract AaveOracle is IOracle {

    using Math for *;

    IPoolAddressesProvider public immutable provider;

    constructor(IPoolAddressesProvider _provider) {
        provider = _provider;
    }

    function rate(IERC20 base, IERC20 quote) external view override returns (uint256) {
        uint256[] memory pricesArr = IAaveOracle(provider.getPriceOracle()).getAssetsPrices(toArray(address(base), address(quote)));
        return pricesArr[0].mulDiv(10 ** quote.decimals(), pricesArr[1]);
    }

}

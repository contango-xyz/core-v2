// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../TestSetup.t.sol";

import "src/moneymarkets/morpho/dependencies/IMorphoOracle.sol";

contract MorphoOracleMock is IMorphoOracle {

    uint256 public constant ORACLE_PRICE_DECIMALS = 36;

    ERC20Data public base;
    ERC20Data public quote;

    constructor(ERC20Data memory _base, ERC20Data memory _quote) {
        base = _base;
        quote = _quote;
    }

    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @dev It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    /// decimals of precision.
    function price() external view returns (uint256) {
        uint256 basePrice = uint256(base.chainlinkUsdOracle.latestAnswer());
        uint256 quotePrice = uint256(quote.chainlinkUsdOracle.latestAnswer());
        uint256 baseDecimals = base.token.decimals();
        uint256 quoteDecimals = quote.token.decimals();

        uint256 priceDecimals = ORACLE_PRICE_DECIMALS + quoteDecimals - baseDecimals;
        uint256 priceUnit = 10 ** priceDecimals;

        return basePrice * priceUnit / quotePrice;
    }

}

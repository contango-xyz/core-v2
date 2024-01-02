//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ICToken.sol";

interface IUniswapAnchoredView {

    struct TokenConfig {
        ICToken cToken;
        address underlying;
        bytes32 symbolHash;
        uint256 baseUnit;
        uint8 priceSource;
        uint256 fixedPrice;
        address uniswapMarket;
        address reporter;
        uint256 reporterMultiplier;
        bool isUniswapReversed;
    }

    function ETH_BASE_UNIT() external view returns (uint256);
    function EXP_SCALE() external view returns (uint256);
    function MAX_INTEGER() external view returns (uint256);
    function MAX_TOKENS() external view returns (uint256);
    function acceptOwnership() external;
    function activateFailover(bytes32 symbolHash) external;
    function anchorPeriod() external view returns (uint32);
    function deactivateFailover(bytes32 symbolHash) external;
    function getTokenConfig(uint256 i) external view returns (TokenConfig memory);
    function getTokenConfigByCToken(ICToken cToken) external view returns (TokenConfig memory);
    function getTokenConfigByReporter(address reporter) external view returns (TokenConfig memory);
    function getTokenConfigBySymbol(string memory symbol) external view returns (TokenConfig memory);
    function getTokenConfigBySymbolHash(bytes32 symbolHash) external view returns (TokenConfig memory);
    function getTokenConfigByUnderlying(address underlying) external view returns (TokenConfig memory);
    function getUnderlyingPrice(ICToken cToken) external view returns (uint256);
    function lowerBoundAnchorRatio() external view returns (uint256);
    function numTokens() external view returns (uint256);
    function owner() external view returns (address);
    function pokeFailedOverPrice(bytes32 symbolHash) external;
    function price(string memory symbol) external view returns (uint256);
    function prices(bytes32) external view returns (uint248 price, bool failoverActive);
    function transferOwnership(address to) external;
    function upperBoundAnchorRatio() external view returns (uint256);
    function validate(uint256, int256, uint256, int256 currentAnswer) external returns (bool valid);

}

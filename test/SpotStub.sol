// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "./stub/ChainlinkAggregatorV2V3Mock.sol";
import "./stub/UniswapPoolStub.sol";

import "./TestSetup.t.sol";

contract SpotStub {

    using SignedMath for int256;

    struct StubUniswapPoolParams {
        address poolAddress;
        IERC20 token0;
        IERC20 token1;
        AggregatorV2V3Interface token0Oracle;
        AggregatorV2V3Interface token1Oracle;
        bool token0Quoted;
        int256 spread;
    }

    address public immutable uniswapFactory;

    constructor(address _uniswapFactory) {
        uniswapFactory = _uniswapFactory;
    }

    function stubPrice(ERC20Data memory base, ERC20Data memory quote, int256 baseUsdPrice, int256 quoteUsdPrice, uint24 uniswapFee)
        public
        returns (address poolAddress)
    {
        return stubPrice({
            base: base,
            quote: quote,
            baseUsdPrice: baseUsdPrice,
            quoteUsdPrice: quoteUsdPrice,
            spread: 0,
            uniswapFee: uniswapFee
        });
    }

    function stubPrice(
        ERC20Data memory base,
        ERC20Data memory quote,
        int256 baseUsdPrice,
        int256 quoteUsdPrice,
        int256 spread,
        uint24 uniswapFee
    ) public returns (address poolAddress) {
        stubChainlinkPrice(baseUsdPrice, address(base.chainlinkUsdOracle));
        stubChainlinkPrice(quoteUsdPrice, address(quote.chainlinkUsdOracle));
        return stubUniswapPrice(base, quote, spread, uniswapFee);
    }

    function stubChainlinkPrice(int256 price, address chainlinkAggregator) public returns (ChainlinkAggregatorV2V3Mock oracle) {
        (bool success, bytes memory returndata) =
            chainlinkAggregator.call(abi.encodeWithSelector(ChainlinkAggregatorV2V3Mock(chainlinkAggregator).decimals.selector));
        // defaults to 8 if v3 interface is not supported
        uint8 decimals = success ? abi.decode(returndata, (uint8)) : 8;
        VM.etch(chainlinkAggregator, VM.getDeployedCode("ChainlinkAggregatorV2V3Mock.sol"));
        oracle = ChainlinkAggregatorV2V3Mock(chainlinkAggregator).setDecimals(decimals).set(price);
    }

    function movePrice(ERC20Data memory data, int256 percentage) public returns (int256 newPrice) {
        require(percentage >= -1e18 && percentage <= 10e18, "Invalid percentage");
        (, int256 currentPrice,,,) = data.chainlinkUsdOracle.latestRoundData();
        newPrice = currentPrice * (percentage + 1e18) / 1e18;
        stubChainlinkPrice(newPrice, address(data.chainlinkUsdOracle));

        console.log("Moved %s price from %s to %s", data.token.symbol(), currentPrice.abs(), newPrice.abs());
    }

    function stubUniswapPrice(ERC20Data memory base, ERC20Data memory quote, int256 spread, uint24 uniswapFee)
        public
        returns (address poolAddress)
    {
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(address(base.token), address(quote.token), uniswapFee);

        IERC20 token0 = IERC20(poolKey.token0);
        IERC20 token1 = IERC20(poolKey.token1);

        AggregatorV2V3Interface token0Oracle = base.token == token0 ? base.chainlinkUsdOracle : quote.chainlinkUsdOracle;
        AggregatorV2V3Interface token1Oracle = base.token == token1 ? base.chainlinkUsdOracle : quote.chainlinkUsdOracle;

        poolAddress = PoolAddress.computeAddress(uniswapFactory, poolKey);

        _stubUniswapPool(
            StubUniswapPoolParams({
                poolAddress: poolAddress,
                token0: token0,
                token1: token1,
                token0Oracle: token0Oracle,
                token1Oracle: token1Oracle,
                token0Quoted: quote.token == token0,
                spread: spread
            })
        );
    }

    function _stubUniswapPool(StubUniswapPoolParams memory params) private {
        VM.etch(
            params.poolAddress,
            address(
                new UniswapPoolStub({
                        _token0: params.token0,
                        _token1: params.token1,
                        _token0Oracle: params.token0Oracle,
                        _token1Oracle: params.token1Oracle,
                        _token0Quoted: params.token0Quoted})
            ).code
        );
        VM.label(params.poolAddress, "UniswapPoolStub");
        UniswapPoolStub(params.poolAddress).setAbsoluteSpread(params.spread);
    }

}

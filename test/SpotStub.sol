// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "forge-std/StdCheats.sol";

import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "./stub/ChainlinkAggregatorV2V3Mock.sol";
import "./stub/UniswapPoolStub.sol";

import "./TestSetup.t.sol";

contract SpotStub is StdCheats {

    using SignedMath for int256;

    struct StubUniswapPoolParams {
        address poolAddress;
        IERC20 token0;
        IERC20 token1;
        IAggregatorV2V3 token0Oracle;
        IAggregatorV2V3 token1Oracle;
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

    function movePrice(ERC20Data memory data, int256 percentage) public returns (int256 newPrice) {
        return movePrice(address(data.chainlinkUsdOracle), string.concat(data.token.symbol(), "/USD"), percentage);
    }

    function movePrice(address oracle, string memory token, int256 percentage) public returns (int256 newPrice) {
        require(percentage >= -1e18 && percentage <= 10e18, "Invalid percentage");
        (, int256 currentPrice,,,) = IAggregatorV2V3(oracle).latestRoundData();
        newPrice = currentPrice * (percentage + 1e18) / 1e18;
        stubChainlinkPrice(newPrice, oracle);

        console.log("Moved %s price from %s to %s", token, currentPrice.abs(), newPrice.abs());
    }

    function stubUniswapPrice(ERC20Data memory base, ERC20Data memory quote, int256 spread, uint24 uniswapFee)
        public
        returns (address poolAddress)
    {
        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(address(base.token), address(quote.token), uniswapFee);

        IERC20 token0 = IERC20(poolKey.token0);
        IERC20 token1 = IERC20(poolKey.token1);

        IAggregatorV2V3 token0Oracle = base.token == token0 ? base.chainlinkUsdOracle : quote.chainlinkUsdOracle;
        IAggregatorV2V3 token1Oracle = base.token == token1 ? base.chainlinkUsdOracle : quote.chainlinkUsdOracle;

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
        deployCodeTo(
            "UniswapPoolStub.sol:UniswapPoolStub",
            abi.encode(params.token0, params.token1, params.token0Oracle, params.token1Oracle, params.token0Quoted),
            params.poolAddress
        );
        VM.label(params.poolAddress, "UniswapPoolStub");
        UniswapPoolStub(params.poolAddress).setAbsoluteSpread(params.spread);
    }

}

function stubChainlinkPrice(int256 price, address chainlinkAggregator) returns (ChainlinkAggregatorV2V3Mock oracle) {
    (bool success, bytes memory returndata) =
        chainlinkAggregator.call(abi.encodeWithSelector(ChainlinkAggregatorV2V3Mock(chainlinkAggregator).decimals.selector));
    // defaults to 8 if v3 interface is not supported
    uint8 decimals = success ? abi.decode(returndata, (uint8)) : 8;
    deployCodeTo("ChainlinkAggregatorV2V3Mock.sol:ChainlinkAggregatorV2V3Mock", chainlinkAggregator);
    oracle = ChainlinkAggregatorV2V3Mock(chainlinkAggregator).setDecimals(decimals).set(price);
}

function deployCodeTo(string memory what, bytes memory args, uint256 value, address where) {
    bytes memory creationCode = VM.getCode(what);
    VM.etch(where, abi.encodePacked(creationCode, args));
    (bool success, bytes memory runtimeBytecode) = where.call{ value: value }("");
    require(success, "StdCheats deployCodeTo(string,bytes,uint256,address): Failed to create runtime bytecode.");
    VM.etch(where, runtimeBytecode);
}

function deployCodeTo(string memory what, address where) {
    deployCodeTo(what, "", 0, where);
}

function deployCodeTo(string memory what, bytes memory args, address where) {
    deployCodeTo(what, args, 0, where);
}

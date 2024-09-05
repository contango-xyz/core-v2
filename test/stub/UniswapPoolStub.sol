//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";

import "src/dependencies/Chainlink.sol";
import "../dependencies/Uniswap.sol";

contract UniswapPoolStub {

    using Math for *;
    using SafeERC20 for IERC20;
    using SignedMath for *;

    event UniswapPoolStubCreated(
        IERC20 token0, IERC20 token1, IAggregatorV2V3 token0Oracle, IAggregatorV2V3 token1Oracle, bool token0Quoted
    );

    event SpreadSet(int256 spread);

    event Swap(address recipient, bool zeroForOne, int256 amount0, int256 amount1, int256 oraclePrice, int256 price);

    error TooMuchRepaid(uint256 expected, uint256 actual, uint256 diff);
    error TooLittleRepaid(uint256 expected, uint256 actual, uint256 diff);

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    IAggregatorV2V3 public immutable token0Oracle;
    IAggregatorV2V3 public immutable token1Oracle;
    bool public immutable token0Quoted;

    int256 public absoluteSpread;

    constructor(IERC20 _token0, IERC20 _token1, IAggregatorV2V3 _token0Oracle, IAggregatorV2V3 _token1Oracle, bool _token0Quoted) {
        token0 = _token0;
        token1 = _token1;
        token0Oracle = _token0Oracle;
        token1Oracle = _token1Oracle;
        token0Quoted = _token0Quoted;

        emit UniswapPoolStubCreated(token0, token1, token0Oracle, token1Oracle, token0Quoted);
    }

    function setAbsoluteSpread(int256 value) external {
        absoluteSpread = value;
        emit SpreadSet(value);
    }

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160, bytes calldata data)
        external
        returns (int256 amount0, int256 amount1)
    {
        int256 oraclePrice = peek();
        int256 price;
        if (token0Quoted) price = zeroForOne ? oraclePrice + absoluteSpread : oraclePrice - absoluteSpread;
        else price = zeroForOne ? oraclePrice - absoluteSpread : oraclePrice + absoluteSpread;

        (amount0, amount1) = _calculateSwap(zeroForOne, amountSpecified, price);

        function(int256, int256, bytes memory) external callback = IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback;
        if (block.chainid == 56) callback = IUniswapV3SwapCallback(msg.sender).pancakeV3SwapCallback;
        if (block.chainid == 534_352) callback = IUniswapV3SwapCallback(msg.sender).ramsesV2SwapCallback;

        if (amount0 < 0) {
            token0.safeTransfer(recipient, uint256(-amount0));
            uint256 expected = token1.balanceOf(address(this)) + uint256(amount1);
            callback(amount0, amount1, data);
            uint256 actual = token1.balanceOf(address(this));
            _validateRepayment(actual, expected);
        } else {
            token1.safeTransfer(recipient, uint256(-amount1));
            uint256 expected = token0.balanceOf(address(this)) + uint256(amount0);
            callback(amount0, amount1, data);
            uint256 actual = token0.balanceOf(address(this));
            _validateRepayment(actual, expected);
        }

        emit Swap({
            recipient: recipient,
            zeroForOne: zeroForOne,
            amount0: amount0,
            amount1: amount1,
            oraclePrice: oraclePrice,
            price: price
        });
    }

    function _calculateSwap(bool zeroForOne, int256 amountSpecified, int256 price) private view returns (int256 amount0, int256 amount1) {
        bool oneForZero = !zeroForOne;
        bool exactInput = amountSpecified > 0;
        bool exactOutput = amountSpecified < 0;

        int256 token0Precision = int256(10 ** token0.decimals());
        int256 token1Precision = int256(10 ** token1.decimals());

        // swap exact input token0 for token1
        // swap token1 for exact output token0
        if ((zeroForOne && exactInput) || (oneForZero && exactOutput)) {
            amount0 = amountSpecified;

            if (token0Quoted) {
                // amount0: token0 precision
                // price: token0 precision
                // amount1: token1 precision
                amount1 = -amount0 * token1Precision / price;
            } else {
                // amount0: token0 precision
                // price: token1 precision
                // amount1: token1 precision
                amount1 = int256(amount0.abs().mulDiv(uint256(price), uint256(token0Precision), Math.Rounding.Up));
                if (exactInput) amount1 = -amount1;
            }
        }

        // swap token0 for exact output token1
        // swap exact input token1 for token0
        if ((zeroForOne && exactOutput) || (oneForZero && exactInput)) {
            amount1 = amountSpecified;

            if (token0Quoted) {
                // amount1: token1 precision
                // price: token0 precision
                // amount0: token0 precision
                amount0 = int256(amount1.abs().mulDiv(uint256(price), uint256(token1Precision), Math.Rounding.Up));
                if (exactInput) amount0 = -amount0;
            } else {
                // amount1: token1 precision
                // price: token1 precision
                // amount0: token0 precision
                amount0 = -amount1 * token0Precision / price;
            }
        }
    }

    function _validateRepayment(uint256 actual, uint256 expected) internal pure {
        if (actual > expected + 5) revert TooMuchRepaid(expected, actual, actual - expected);
        if (actual < expected) revert TooLittleRepaid(expected, actual, expected - actual);
    }

    function peek() internal view returns (int256 price) {
        IAggregatorV2V3 baseOracle = token0Quoted ? token1Oracle : token0Oracle;
        IAggregatorV2V3 quoteOracle = token0Quoted ? token0Oracle : token1Oracle;

        int256 baseOraclePrecision = int256(10 ** baseOracle.decimals());
        int256 quoteOraclePrecision = int256(10 ** quoteOracle.decimals());

        int256 basePrice = baseOracle.latestAnswer();
        int256 quotePrice = quoteOracle.latestAnswer();

        address quote = address(token0Quoted ? token0 : token1);

        int256 quotePrecision = int256(10 ** IERC20(quote).decimals());

        price = (basePrice * quoteOraclePrecision * quotePrecision) / (quotePrice * baseOraclePrecision);
    }

}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "./UniswapPoolStub.sol";
import "./ChainlinkAggregatorV2V3Mock.sol";

import "../TestSetup.t.sol";

contract UniswapPoolStubTest is IUniswapV3SwapCallback, Test {

    struct AssertionData {
        int256 expectedAmount0Delta;
        int256 expectedAmount1Delta;
        IERC20 repaymentToken;
    }

    Env internal env;
    UniswapPoolStub internal sut;

    function setUp() public virtual {
        env = new ArbitrumEnv();
        env.init();
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) public virtual override {
        AssertionData memory assertionData = abi.decode(data, (AssertionData));

        assertEqDecimal(amount0Delta, assertionData.expectedAmount0Delta, sut.token0().decimals(), "amount0Delta");
        assertEqDecimal(amount1Delta, assertionData.expectedAmount1Delta, sut.token1().decimals(), "amount1Delta");

        uint256 repayment = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        deal(address(assertionData.repaymentToken), address(this), repayment);
        assertionData.repaymentToken.transfer(msg.sender, repayment);
    }

    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }

    function ramsesV2SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }

}

contract UniswapPoolStubETHUSDCTest is UniswapPoolStubTest {

    function setUp() public override {
        super.setUp();

        ChainlinkAggregatorV2V3Mock ethOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(1000e8);
        ChainlinkAggregatorV2V3Mock usdcOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(1e8);

        sut = new UniswapPoolStub({
            _token0: env.token(WETH),
            _token1: env.token(USDC),
            _token0Oracle: ethOracle,
            _token1Oracle: usdcOracle,
            _token0Quoted: false
        });
        sut.setAbsoluteSpread(1e6);

        deal(address(env.token(WETH)), address(sut), 100_000 ether);
        deal(address(env.token(USDC)), address(sut), 1_000_000e6);
    }

    function testSwapZeroForOneExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 1 ether, expectedAmount1Delta: -999e6, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, 1 ether, 0, abi.encode(assertionData));
    }

    function testSwapZeroForOneExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 1 ether, expectedAmount1Delta: -999e6, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, -999e6, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -1 ether, expectedAmount1Delta: 1001e6, repaymentToken: env.token(USDC) });
        sut.swap(address(this), false, 1001e6, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -1 ether, expectedAmount1Delta: 1001e6, repaymentToken: env.token(USDC) });
        sut.swap(address(this), false, -1 ether, 0, abi.encode(assertionData));
    }

}

contract UniswapPoolStubETHDAITest is UniswapPoolStubTest {

    function setUp() public override {
        super.setUp();

        ChainlinkAggregatorV2V3Mock ethOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(1000e8);
        ChainlinkAggregatorV2V3Mock daiOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(1e8);

        sut = new UniswapPoolStub({
            _token0: env.token(WETH),
            _token1: env.token(DAI),
            _token0Oracle: ethOracle,
            _token1Oracle: daiOracle,
            _token0Quoted: false
        });
        sut.setAbsoluteSpread(1e18);

        deal(address(env.token(WETH)), address(sut), 100_000 ether);
        deal(address(env.token(DAI)), address(sut), 1_000_000e18);
    }

    function testSwapZeroForOneExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 1 ether, expectedAmount1Delta: -999e18, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, 1 ether, 0, abi.encode(assertionData));
    }

    function testSwapZeroForOneExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 1 ether, expectedAmount1Delta: -999e18, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, -999e18, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -1 ether, expectedAmount1Delta: 1001e18, repaymentToken: env.token(DAI) });
        sut.swap(address(this), false, 1001e18, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -1 ether, expectedAmount1Delta: 1001e18, repaymentToken: env.token(DAI) });
        sut.swap(address(this), false, -1 ether, 0, abi.encode(assertionData));
    }

}

contract UniswapPoolStubETHLINKTest is UniswapPoolStubTest {

    function setUp() public override {
        super.setUp();

        ChainlinkAggregatorV2V3Mock ethOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(1000e8);
        ChainlinkAggregatorV2V3Mock linkOracle = new ChainlinkAggregatorV2V3Mock().setDecimals(8).set(5e8);

        sut = new UniswapPoolStub({
            _token0: env.token(WETH),
            _token1: env.token(LINK),
            _token0Oracle: ethOracle,
            _token1Oracle: linkOracle,
            _token0Quoted: false
        });
        sut.setAbsoluteSpread(1e18); // 199 / 201

        deal(address(env.token(WETH)), address(sut), 100_000 ether);
        deal(address(env.token(LINK)), address(sut), 1_000_000e18);
    }

    function testSwapZeroForOneExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 2 ether, expectedAmount1Delta: -398e18, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, 2 ether, 0, abi.encode(assertionData));
    }

    function testSwapZeroForOneExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: 2 ether, expectedAmount1Delta: -398e18, repaymentToken: env.token(WETH) });
        sut.swap(address(this), true, -398e18, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactInput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -2 ether, expectedAmount1Delta: 402e18, repaymentToken: env.token(LINK) });
        sut.swap(address(this), false, 402e18, 0, abi.encode(assertionData));
    }

    function testSwapOneForZeroExactOutput() public {
        AssertionData memory assertionData =
            AssertionData({ expectedAmount0Delta: -2 ether, expectedAmount1Delta: 402e18, repaymentToken: env.token(LINK) });
        sut.swap(address(this), false, -2 ether, 0, abi.encode(assertionData));
    }

}

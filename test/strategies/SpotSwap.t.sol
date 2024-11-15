//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";
import "../BaseTest.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract SpotSwapTest is BaseTest, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;
    using { positionsUpserted } for Vm.Log[];

    Env internal env;
    IVault internal vault;
    SimpleSpotExecutor internal spotExecutor;
    SwapRouter02 internal router;
    IERC20 internal weth;
    IERC20 internal usdc;
    IERC20 internal dai;
    IERC20 internal wstEth;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(195_104_100);

        vault = env.vault();
        trader = env.positionActions().trader();
        traderPK = env.positionActions().traderPk();
        spotExecutor = env.maestro().spotExecutor();
        router = env.uniswapRouter();

        weth = env.token(WETH);
        usdc = env.token(USDC);
        dai = env.token(DAI);

        sut = env.strategyBuilder();

        env.spotStub().stubPrice({ base: env.erc20(WETH), quote: env.erc20(USDC), baseUsdPrice: 1000e8, quoteUsdPrice: 1e8, uniswapFee: 500 });

        env.spotStub().stubPrice({
            base: env.erc20(USDC),
            quote: env.erc20(DAI),
            baseUsdPrice: 0.999e8,
            quoteUsdPrice: 1.0001e8,
            uniswapFee: 500
        });
    }

    modifier invariants() {
        _;

        assertEqDecimal(usdc.balanceOf(address(vault)), 0, 18, "vault has USDC balance");
        assertEqDecimal(weth.balanceOf(address(vault)), 0, 6, "vault has ETH balance");
        assertEqDecimal(dai.balanceOf(address(vault)), 0, 18, "vault has DAI balance");

        assertEqDecimal(usdc.balanceOf(address(sut)), 0, 18, "strategy has USDC balance");
        assertEqDecimal(weth.balanceOf(address(sut)), 0, 6, "strategy has ETH balance");
        assertEqDecimal(dai.balanceOf(address(sut)), 0, 18, "strategy has DAI balance");
    }

    function testSpotSwap_Permit() public invariants {
        uint256 quantity = 1000e18;
        IERC20 sell = dai;
        IERC20 buy = usdc;

        EIP2098Permit memory signedPermit = env.dealAndPermit(sell, trader, traderPK, quantity, address(sut));
        SwapData memory swapData = _swap(router, sell, buy, quantity, address(spotExecutor));

        steps.push(StepCall(Step.PullFundsWithPermit, abi.encode(sell, signedPermit, quantity, spotExecutor)));
        steps.push(StepCall(Step.Swap, abi.encode(swapData, sell, buy, trader)));

        vm.prank(trader);
        sut.process(steps);

        assertEqDecimal(sell.balanceOf(trader), 0, 18, "sell balance");
        assertEqDecimal(buy.balanceOf(trader), 1001.101101e6, 6, "buy balance");
    }

    function testSpotSwap_Permit2() public invariants {
        uint256 quantity = 1000e18;
        IERC20 sell = dai;
        IERC20 buy = usdc;

        EIP2098Permit memory signedPermit = env.dealAndPermit2(sell, trader, traderPK, quantity, address(sut));
        SwapData memory swapData = _swap(router, sell, buy, quantity, address(spotExecutor));

        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(sell, signedPermit, quantity, spotExecutor)));
        steps.push(StepCall(Step.Swap, abi.encode(swapData, sell, buy, trader)));

        vm.prank(trader);
        sut.process(steps);

        assertEqDecimal(sell.balanceOf(trader), 0, 18, "sell balance");
        assertEqDecimal(buy.balanceOf(trader), 1001.101101e6, 6, "buy balance");
    }

    function testSpotSwap_FromNative() public invariants {
        uint256 quantity = 1 ether;
        IERC20 sell = weth;
        IERC20 buy = usdc;

        vm.deal(trader, quantity);
        SwapData memory swapData = _swap(router, sell, buy, quantity, address(spotExecutor));

        steps.push(StepCall(Step.WrapNativeToken, abi.encode(spotExecutor)));
        steps.push(StepCall(Step.Swap, abi.encode(swapData, sell, buy, trader)));

        vm.prank(trader);
        sut.process{ value: quantity }(steps);

        assertEqDecimal(sell.balanceOf(trader), 0, 18, "sell balance");
        assertEqDecimal(buy.balanceOf(trader), 1001.001001e6, 6, "buy balance");
    }

    function testSpotSwap_ToNative() public invariants {
        uint256 quantity = 1000e6;
        IERC20 sell = usdc;
        IERC20 buy = weth;

        EIP2098Permit memory signedPermit = env.dealAndPermit(sell, trader, traderPK, quantity, address(sut));
        SwapData memory swapData = _swap(router, sell, buy, quantity, address(spotExecutor));

        steps.push(StepCall(Step.PullFundsWithPermit, abi.encode(sell, signedPermit, quantity, spotExecutor)));
        steps.push(StepCall(Step.Swap, abi.encode(swapData, sell, buy, sut)));
        // steps.push(StepCall(Step.UnwrapNativeToken, abi.encode(sut.BALANCE(), trader)));

        vm.prank(trader);
        sut.process(steps);

        assertEqDecimal(sell.balanceOf(trader), 0, 18, "sell balance");
        assertEqDecimal(trader.balance, 0.999000090580999 ether, 18, "buy balance");
    }

}

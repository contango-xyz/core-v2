//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract CrossStableFundingRateFarmTest is Test, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    Contango internal contango;
    ContangoLens internal lens;
    PositionNFT internal positionNFT;
    IVault internal vault;
    TestInstrument internal longInstrument;
    TestInstrument internal shortInstrument;
    PositionId internal _longPositionId;
    PositionId internal _shortPositionId;
    IERC7399 internal flashLoanProvider;
    SimpleSpotExecutor internal spotExecutor;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();

        contango = env.contango();
        lens = env.contangoLens();
        positionNFT = env.positionNFT();
        vault = env.vault();
        flashLoanProvider = env.tsQuoter().flashLoanProviders(0);
        longInstrument = env.createInstrument(env.erc20(WETH), env.erc20(DAI));
        shortInstrument = env.createInstrument(env.erc20(USDC), env.erc20(WETH));
        (trader, traderPK) = makeAddrAndKey("trader");
        spotExecutor = env.maestro().spotExecutor();

        sut = env.strategyBuilder();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(DAI).chainlinkUsdOracle));

        _longPositionId = env.encoder().encodePositionId(longInstrument.symbol, MM_AAVE, PERP, 0);
        _shortPositionId = env.encoder().encodePositionId(shortInstrument.symbol, MM_EXACTLY, PERP, 0);
    }

    modifier invariants() {
        _;

        assertEqDecimal(env.token(USDC).balanceOf(address(vault)), 0, 6, "vault has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(vault)), 0, 18, "vault has ETH balance");
        assertEqDecimal(env.token(DAI).balanceOf(address(vault)), 0, 18, "vault has DAI balance");

        assertEqDecimal(env.token(USDC).balanceOf(address(sut)), 0, 6, "strategy has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(sut)), 0, 18, "strategy has ETH balance");
        assertEqDecimal(env.token(DAI).balanceOf(address(sut)), 0, 18, "strategy has DAI balance");
    }

    function _open(uint256 cashflow, uint256 shortQty, uint256 longQty)
        internal
        returns (PositionId longPositionId, PositionId shortPositionId)
    {
        EIP2098Permit memory signedPermit = env.dealAndPermit2(shortInstrument.base, trader, traderPK, cashflow, address(sut));
        uint256 flashLoanAmount = shortQty - cashflow;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.base), flashLoanAmount);

        uint256 amountIn = (flashLoanAmount + flashLoanFee) * 1e12;

        FancySpot spot = new FancySpot();
        deal(address(shortInstrument.base), address(spot), flashLoanAmount + flashLoanFee);
        SwapData memory swapData = SwapData({
            router: address(spot),
            spender: address(spot),
            amountIn: amountIn,
            minAmountOut: flashLoanAmount + flashLoanFee,
            swapBytes: abi.encodeWithSelector(
                spot.swap.selector, longInstrument.quote, amountIn, shortInstrument.base, flashLoanAmount + flashLoanFee
            )
        });

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.base, flashLoanAmount)));
        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(shortInstrument.base, signedPermit, cashflow, vault)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.base, shortQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(_shortPositionId, POSITION_TWO, shortQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, longQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(_longPositionId, POSITION_ONE, longQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_ONE, amountIn)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, longInstrument.quote, shortInstrument.base)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.base, flashLoanAmount + flashLoanFee)));

        vm.prank(trader);
        snapStart("CrossStableFarmPosition:Open");
        StepResult[] memory results = sut.process(steps);
        snapEnd();

        longPositionId = abi.decode(results[5].data, (PositionId));
        shortPositionId = abi.decode(results[3].data, (PositionId));
    }

    function testOpen() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 10 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 5000e18, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 15_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function testClose() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        skip(365 days);
        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(
            longBalances.collateral, 10.145615749608335812 ether, 1, longInstrument.baseDecimals, "longBalances.collateral"
        );
        assertApproxEqAbsDecimal(longBalances.debt, 5172.899690361642072227e18, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 15_252.808197e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10.361650180015496161 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        FancySpot spot = new FancySpot();
        deal(address(shortInstrument.quote), address(spot), 0.3 ether);
        SwapData memory swapData1 = SwapData({
            router: address(spot),
            spender: address(spot),
            amountIn: 300e6,
            minAmountOut: 0.3 ether,
            swapBytes: abi.encodeWithSelector(spot.swap.selector, shortInstrument.base, 300e6, shortInstrument.quote, 0.3 ether)
        });
        deal(address(longInstrument.quote), address(spot), 5200e18);
        SwapData memory swapData2 = SwapData({
            router: address(spot),
            spender: address(spot),
            amountIn: 5200e6,
            minAmountOut: 5200e18,
            swapBytes: abi.encodeWithSelector(spot.swap.selector, shortInstrument.base, 5200e6, longInstrument.quote, 5200e18)
        });

        uint256 flashLoanAmount = shortBalances.debt * 1.001e18 / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.quote), flashLoanAmount);

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(shortPositionId, POSITION_TWO, flashLoanAmount)));
        steps.push(StepCall(Step.PositionClose, abi.encode(shortPositionId, POSITION_TWO)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData2, shortInstrument.base, longInstrument.quote)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(longPositionId, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(longPositionId, POSITION_ONE)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData1, shortInstrument.base, shortInstrument.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.quote, flashLoanAmount + flashLoanFee)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.base, sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.quote, sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(longInstrument.quote, sut.BALANCE(), trader)));

        snapStart("CrossStableFarmPosition:Close");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(longPositionId), "longPositionId exists");
        assertFalse(positionNFT.exists(shortPositionId), "shortPositionId exists");

        assertApproxEqAbsDecimal(shortInstrument.base.balanceOf(trader), 9752.808197e6, 1, shortInstrument.baseDecimals, "quote cashflow");
        assertApproxEqAbsDecimal(trader.balance, 0.083965569592839651 ether, 1, shortInstrument.quoteDecimals, "base cashflow");
        assertApproxEqAbsDecimal(
            longInstrument.quote.balanceOf(trader), 27.100309638357927773e18, 1, longInstrument.quoteDecimals, "quote 2 cashflow"
        );
    }

}

contract FancySpot {

    function swap(IERC20 sell, uint256 sellAmount, IERC20 buy, uint256 buyAmount) external {
        sell.transferFrom(msg.sender, address(this), sellAmount);
        buy.transfer(msg.sender, buyAmount);
    }

}

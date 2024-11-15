//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";
import "../BaseTest.sol";

import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract DecreasePositionFlashloanQuoteTest is BaseTest, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;
    using { positionsUpserted } for Vm.Log[];

    Env internal env;
    Contango internal contango;
    ContangoLens internal lens;
    PositionNFT internal positionNFT;
    IVault internal vault;
    TestInstrument internal ethUsdc;
    IERC7399 internal flashLoanProvider;
    SimpleSpotExecutor internal spotExecutor;
    SwapRouter02 internal router;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(19_519_641);

        contango = env.contango();
        lens = env.contangoLens();
        positionNFT = env.positionNFT();
        vault = env.vault();
        flashLoanProvider = env.tsQuoter().flashLoanProviders(0);
        ethUsdc = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        trader = env.positionActions().trader();
        traderPK = env.positionActions().traderPk();
        spotExecutor = env.maestro().spotExecutor();
        router = env.uniswapRouter();

        sut = env.strategyBuilder();

        env.spotStub().stubPrice({
            base: ethUsdc.baseData,
            quote: ethUsdc.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            spread: 0.5e6,
            uniswapFee: 500
        });
    }

    modifier invariants() {
        _;

        assertEqDecimal(ethUsdc.quote.balanceOf(address(vault)), 0, ethUsdc.quoteDecimals, "vault has USDC balance");
        assertLeDecimal(ethUsdc.base.balanceOf(address(vault)), 0.00001e18, ethUsdc.baseDecimals, "vault has ETH balance");

        assertEqDecimal(ethUsdc.quote.balanceOf(address(sut)), 0, ethUsdc.quoteDecimals, "strategy has USDC balance");
        assertEqDecimal(ethUsdc.base.balanceOf(address(sut)), 0, ethUsdc.baseDecimals, "strategy has ETH balance");
    }

    function testScenario16() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 3900e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, decreaseAmount, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.BALANCE())));

        snapStart("DecreasePositionFlashloanQuote:Scenario16");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        Balances memory balances = lens.balances(existingPosition);
        assertApproxEqAbsDecimal(balances.collateral, 5.995002550689603566 ether, 1, ethUsdc.baseDecimals, "collateral");
        assertApproxEqAbsDecimal(balances.debt, 2002.000257e6, 1, ethUsdc.quoteDecimals, "debt");
    }

    function testScenario17() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        PositionPermit memory positionPermit = env.positionIdPermit2(existingPosition, trader, traderPK, address(sut));

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 4900e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        uint256 depositAmount = 1 ether;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, decreaseAmount + depositAmount, address(spotExecutor));
        vm.deal(trader, depositAmount);

        skip(10 seconds);

        steps.push(StepCall(Step.VaultDepositNative, ""));
        steps.push(StepCall(Step.PullPosition, abi.encode(positionPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.BALANCE())));

        snapStart("DecreasePositionFlashloanQuote:Scenario17");
        vm.prank(trader);
        sut.process{ value: depositAmount }(steps);
        snapEnd();

        Balances memory balances = lens.balances(existingPosition);
        assertApproxEqAbsDecimal(balances.collateral, 5.995002550689603566 ether, 1, ethUsdc.baseDecimals, "collateral");
        assertApproxEqAbsDecimal(balances.debt, 1002.500257e6, 1, ethUsdc.quoteDecimals, "debt");
    }

    function testScenario18() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 3900e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        uint256 depositAmount = 1000e6;
        EIP2098Permit memory signedPermit = env.dealAndPermit2(ethUsdc.quote, trader, traderPK, depositAmount, address(sut));
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, decreaseAmount, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(ethUsdc.quote, signedPermit, depositAmount, vault)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount + depositAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount + depositAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.BALANCE())));

        snapStart("DecreasePositionFlashloanQuote:Scenario18");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        Balances memory balances = lens.balances(existingPosition);
        assertApproxEqAbsDecimal(balances.collateral, 5.995002550689603566 ether, 1, ethUsdc.baseDecimals, "collateral");
        assertApproxEqAbsDecimal(balances.debt, 1002.000257e6, 1, ethUsdc.quoteDecimals, "debt");
    }

    function testScenario19() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 2500e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, 2.505 ether, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdrawNative, abi.encode(sut.BALANCE(), trader)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.BALANCE())));

        snapStart("DecreasePositionFlashloanQuote:Scenario19");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertApproxEqAbsDecimal(trader.balance, 1.495000000000012598 ether, 1, ethUsdc.baseDecimals, "cashflow");
    }

    function testScenario21() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 2500e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, decreaseAmount, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("DecreasePositionFlashloanQuote:Scenario21");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(address(trader)), 1498e6, 1, ethUsdc.quoteDecimals, "cashflow");
    }

    function testScenario23() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = lens.balances(existingPosition);
        uint256 flashLoanAmount = balances.debt * 1.001e18 / 1e18;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, 6.005 ether, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdrawNative, abi.encode(sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("DecreasePositionFlashloanQuote:Scenario23");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");

        assertApproxEqAbsDecimal(trader.balance, 3.990002550689616164 ether, 1, ethUsdc.baseDecimals, "cashflow");
        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(address(trader)), 1.997243e6, 1, ethUsdc.quoteDecimals, "dust");
    }

    function testScenario24() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = lens.balances(existingPosition);
        uint256 flashLoanAmount = balances.debt * 1.001e18 / 1e18;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, balances.collateral, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("DecreasePositionFlashloanQuote:Scenario24");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(trader), 3990.004741e6, 1, ethUsdc.quoteDecimals, "cashflow");
    }

    function testScenario30() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 2900e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, 3.005 ether, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdrawNative, abi.encode(sut.BALANCE(), trader)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.BALANCE())));

        snapStart("DecreasePositionFlashloanQuote:Scenario30");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertApproxEqAbsDecimal(trader.balance, 0.995000000000012598 ether, 1, ethUsdc.baseDecimals, "cashflow");
    }

    function testScenario31() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        uint256 decreaseAmount = 4 ether;
        uint256 flashLoanAmount = 3000e6;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        SwapData memory swapData = _swap(router, ethUsdc.base, ethUsdc.quote, 4 ether, address(spotExecutor));

        skip(10 seconds);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, flashLoanAmount)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(existingPosition, POSITION_ONE, decreaseAmount)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethUsdc.base, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("DecreasePositionFlashloanQuote:Scenario31");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(address(trader)), 998e6, 1, ethUsdc.quoteDecimals, "cashflow");
    }

}

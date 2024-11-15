//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";
import "../BaseTest.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract MigratePositionTest is BaseTest, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;
    using { positionsUpserted, strategyExecuted } for Vm.Log[];

    Env internal env;
    Contango internal contango;
    ContangoLens internal lens;
    PositionNFT internal positionNFT;
    IVault internal vault;
    TestInstrument internal ethUsdc;
    TestInstrument internal ethDai;
    TestInstrument internal wstethDai;
    IERC7399 internal flashLoanProvider;
    SimpleSpotExecutor internal spotExecutor;
    SwapRouter02 internal router;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(20_778_743);

        contango = env.contango();
        lens = env.contangoLens();
        positionNFT = env.positionNFT();
        vault = env.vault();
        flashLoanProvider = env.tsQuoter().flashLoanProviders(0);
        ethUsdc = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        wstethDai = env.createInstrument(env.erc20(WSTETH), env.erc20(DAI));
        ethDai = env.createInstrument(env.erc20(WETH), env.erc20(DAI));
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
            uniswapFee: 500
        });

        env.spotStub().stubPrice({
            base: ethUsdc.quoteData,
            quote: ethDai.quoteData,
            baseUsdPrice: 0.999e8,
            quoteUsdPrice: 1.0001e8,
            uniswapFee: 500
        });

        address wstEthEthPool = env.spotStub().stubPrice({
            base: wstethDai.baseData,
            quote: ethUsdc.baseData,
            baseUsdPrice: 1150e8,
            quoteUsdPrice: 1000e8,
            uniswapFee: 500
        });

        deal(address(wstethDai.baseData.token), wstEthEthPool, type(uint96).max);
    }

    modifier invariants() {
        _;

        assertLeDecimal(ethUsdc.quote.balanceOf(address(vault)), 0.02e6, ethUsdc.quoteDecimals, "vault has USDC balance");
        assertLeDecimal(ethUsdc.base.balanceOf(address(vault)), 0.00002e18, ethUsdc.baseDecimals, "vault has ETH balance");
        assertLeDecimal(ethDai.quote.balanceOf(address(vault)), 0.02e18, ethDai.quoteDecimals, "vault has DAI balance");
        assertLeDecimal(wstethDai.base.balanceOf(address(vault)), 0.00002e18, wstethDai.baseDecimals, "vault has WSTETH balance");

        assertEqDecimal(ethUsdc.quote.balanceOf(address(sut)), 0, ethUsdc.quoteDecimals, "strategy has USDC balance");
        assertEqDecimal(ethUsdc.base.balanceOf(address(sut)), 0, ethUsdc.baseDecimals, "strategy has ETH balance");
        assertEqDecimal(ethDai.quote.balanceOf(address(sut)), 0, ethDai.quoteDecimals, "strategy has DAI balance");
        assertEqDecimal(wstethDai.base.balanceOf(address(sut)), 0, wstethDai.baseDecimals, "strategy has WSTETH balance");
    }

    function testMigrateSameQuoteDifferentMarket() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ContangoLens.MetaData memory meta = lens.metaData(existingPosition);
        uint256 borrowingRatePer10Mins = WAD + meta.rates.borrowing / 52_560;
        uint256 flashLoanAmount = meta.balances.debt * borrowingRatePer10Mins / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        PositionId newPosition = env.encoder().encodePositionId(ethUsdc.symbol, MM_COMPOUND, PERP, 0);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(newPosition, POSITION_TWO, sut.BALANCE())));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, flashLoanAmount + flashLoanFee)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, flashLoanAmount + flashLoanFee)));

        snapStart("MigratePositionTest:SameQuoteDifferentMarket");
        vm.prank(trader);
        skip(10 seconds);
        vm.recordLogs();
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");
        assertEq(contango.lastOwner(existingPosition), trader, "lastOwner");

        PositionId[] memory positions = vm.getRecordedLogs().positionsUpserted();
        assertEq(positions.length, 4);
        newPosition = positions[3];

        assertEq(positionNFT.positionOwner(newPosition), trader);
        Balances memory newBalances = lens.balances(newPosition);
        assertEqDecimal(newBalances.debt, flashLoanAmount + flashLoanFee, ethUsdc.quoteDecimals, "debt");
        assertGeDecimal(newBalances.collateral, meta.balances.collateral, ethUsdc.baseDecimals, "collateral");
    }

    function testMigrateSameQuoteDifferentMarket_MergeWithExistent() public invariants {
        (, PositionId existingPositionOnNewMarket,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 20 ether,
            cashflow: 8000e6,
            cashflowCcy: Currency.Quote
        });
        Balances memory existingBalances = lens.balances(existingPositionOnNewMarket);
        PositionPermit memory existingPositionPermit = env.positionIdPermit2(existingPositionOnNewMarket, trader, traderPK, address(sut));

        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ContangoLens.MetaData memory meta = lens.metaData(existingPosition);
        uint256 borrowingRatePer10Mins = WAD + meta.rates.borrowing / 52_560;
        uint256 flashLoanAmount = meta.balances.debt * borrowingRatePer10Mins / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);

        steps.push(StepCall(Step.PullPosition, abi.encode(existingPositionPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(existingPositionOnNewMarket, POSITION_TWO, sut.BALANCE())));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(existingPositionOnNewMarket, POSITION_TWO, flashLoanAmount + flashLoanFee)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, flashLoanAmount + flashLoanFee)));

        snapStart("MigratePositionTest:SameQuoteDifferentMarket_MergeWithExistent");
        vm.prank(trader);
        skip(10 seconds);
        vm.recordLogs();
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");
        assertEq(contango.lastOwner(existingPosition), trader, "lastOwner");

        PositionId[] memory positions = vm.getRecordedLogs().positionsUpserted();
        assertEq(positions.length, 4);

        assertEq(existingPositionOnNewMarket.asUint(), positions[3].asUint());
        assertEq(positionNFT.positionOwner(existingPositionOnNewMarket), trader);
        Balances memory newBalances = lens.balances(existingPositionOnNewMarket);
        assertApproxEqAbsDecimal(newBalances.debt, existingBalances.debt + flashLoanAmount + flashLoanFee, 600, 18, "debt");
        assertGeDecimal(newBalances.collateral, existingBalances.collateral + 1, 18, "collateral");
    }

    function testMigrateDifferentQuoteSameMarket() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ContangoLens.MetaData memory meta = lens.metaData(existingPosition);
        uint256 borrowingRatePer10Mins = WAD + meta.rates.borrowing / 52_560;
        uint256 flashLoanAmount = meta.balances.debt * borrowingRatePer10Mins / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        PositionId newPosition = env.encoder().encodePositionId(ethDai.symbol, MM_AAVE, PERP, 0);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        uint256 repayAmountInDai = repayAmount * 1e12;
        uint256 repayAmountInDaiWithBuffer = repayAmountInDai * 1.001e18 / WAD;
        SwapData memory swapData = _swap(router, ethDai.quote, ethUsdc.quote, repayAmountInDaiWithBuffer, address(spotExecutor));

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(newPosition, POSITION_TWO, sut.BALANCE())));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, repayAmountInDaiWithBuffer)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethDai.quote, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("MigratePositionTest:DifferentQuoteSameMarket");
        vm.prank(trader);
        skip(10 seconds);
        vm.recordLogs();
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");
        assertEq(contango.lastOwner(existingPosition), trader, "lastOwner");

        PositionId[] memory positions = vm.getRecordedLogs().positionsUpserted();
        assertEq(positions.length, 4);
        newPosition = positions[3];

        assertEq(positionNFT.positionOwner(newPosition), trader);
        Balances memory newBalances = lens.balances(newPosition);
        assertApproxEqAbsDecimal(newBalances.debt, repayAmountInDaiWithBuffer, 1, 18, "debt");
        assertGeDecimal(newBalances.collateral, meta.balances.collateral, ethUsdc.baseDecimals, "collateral");

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(trader), 12.639863e6, 1, ethUsdc.quoteDecimals, "buffer");
    }

    function testMigrateDifferentQuoteDifferentMarket() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ContangoLens.MetaData memory meta = lens.metaData(existingPosition);
        uint256 borrowingRatePer10Mins = WAD + meta.rates.borrowing / 52_560;
        uint256 flashLoanAmount = meta.balances.debt * borrowingRatePer10Mins / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        PositionId newPosition = env.encoder().encodePositionId(ethDai.symbol, MM_COMPOUND, PERP, 0);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        uint256 repayAmountInDai = repayAmount * 1e12;
        uint256 repayAmountInDaiWithBuffer = repayAmountInDai * 1.001e18 / WAD;
        SwapData memory swapData = _swap(router, ethDai.quote, ethUsdc.quote, repayAmountInDaiWithBuffer, address(spotExecutor));

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(newPosition, POSITION_TWO, sut.BALANCE())));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, repayAmountInDaiWithBuffer)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, ethDai.quote, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));

        snapStart("MigratePositionTest:DifferentQuoteDifferentMarket");
        vm.prank(trader);
        skip(10 seconds);
        vm.recordLogs();
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");
        assertEq(contango.lastOwner(existingPosition), trader, "lastOwner");

        PositionId[] memory positions = vm.getRecordedLogs().positionsUpserted();
        assertEq(positions.length, 4);
        newPosition = positions[3];

        assertEq(positionNFT.positionOwner(newPosition), trader);
        Balances memory newBalances = lens.balances(newPosition);
        assertEqDecimal(newBalances.debt, repayAmountInDaiWithBuffer, ethDai.quoteDecimals, "debt");
        assertGeDecimal(newBalances.collateral, meta.balances.collateral, ethUsdc.baseDecimals, "collateral");

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(trader), 12.639863e6, 1, ethUsdc.quoteDecimals, "buffer");
    }

    function testMigrateDifferentBaseDifferentQuoteDifferentMarket() public invariants {
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        ContangoLens.MetaData memory meta = lens.metaData(existingPosition);
        uint256 borrowingRatePer10Mins = WAD + meta.rates.borrowing / 52_560;
        uint256 flashLoanAmount = meta.balances.debt * borrowingRatePer10Mins / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(ethUsdc.quote), flashLoanAmount);
        PositionId newPosition = env.encoder().encodePositionId(wstethDai.symbol, MM_SPARK_SKY, PERP, 0);
        uint256 repayAmount = flashLoanAmount + flashLoanFee;
        uint256 repayAmountInDai = repayAmount * 1e12;
        uint256 repayAmountInDaiWithBuffer = repayAmountInDai * 1.001e18 / WAD;
        SwapData memory quoteSwapData = _swap(router, ethDai.quote, ethUsdc.quote, repayAmountInDaiWithBuffer, address(spotExecutor));
        SwapData memory baseSwapData = _swap(router, ethUsdc.base, wstethDai.base, meta.balances.collateral, address(spotExecutor));

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(ethUsdc.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(existingPosition, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(existingPosition, POSITION_ONE)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(baseSwapData, ethUsdc.base, wstethDai.base)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(newPosition, POSITION_TWO, sut.BALANCE())));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, repayAmountInDaiWithBuffer)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(quoteSwapData, ethDai.quote, ethUsdc.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(ethUsdc.quote, repayAmount)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(ethUsdc.quote, sut.BALANCE(), trader)));
        steps.push(StepCall(Step.EmitEvent, abi.encode(bytes32("PositionMigrated"), "some data")));

        snapStart("MigratePositionTest:DifferentBaseDifferentQuoteDifferentMarket");
        vm.prank(trader);
        skip(10 seconds);
        vm.recordLogs();
        positionNFT.safeTransferFrom(trader, address(sut), existingPosition.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(existingPosition), "existingPosition exists");
        assertEq(contango.lastOwner(existingPosition), trader, "lastOwner");

        StrategyExecuted memory e = vm.getRecordedLogs().strategyExecuted();
        assertEq(e.user, trader);
        assertEq(e.action, "PositionMigrated");
        assertEq(e.data, "some data");
        assertEq(e.position1.asUint(), existingPosition.asUint());
        newPosition = e.position2;

        assertEq(positionNFT.positionOwner(newPosition), trader);
        Balances memory newBalances = lens.balances(newPosition);
        assertEqDecimal(newBalances.debt, repayAmountInDaiWithBuffer, ethUsdc.quoteDecimals, "debt");
        assertEqDecimal(newBalances.collateral, 8.695652173913043478e18, 18);

        assertApproxEqAbsDecimal(ethUsdc.quote.balanceOf(trader), 12.639863e6, 1, ethUsdc.quoteDecimals, "buffer");
    }

}

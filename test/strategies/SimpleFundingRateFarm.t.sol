//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract SimpleFundingRateFarmTest is Test, GasSnapshot {

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
        env = provider(Network.Arbitrum);
        env.init();

        contango = env.contango();
        lens = env.contangoLens();
        positionNFT = env.positionNFT();
        vault = env.vault();
        flashLoanProvider = env.tsQuoter().flashLoanProviders(0);
        longInstrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        shortInstrument = env.createInstrument(env.erc20(USDC), env.erc20(WETH));
        (trader, traderPK) = makeAddrAndKey("trader");
        spotExecutor = env.maestro().spotExecutor();

        sut = env.strategyBuilder();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));

        _longPositionId = env.encoder().encodePositionId(longInstrument.symbol, MM_AAVE, PERP, 0);
        _shortPositionId = env.encoder().encodePositionId(shortInstrument.symbol, MM_RADIANT, PERP, 0);
    }

    modifier invariants() {
        _;

        assertEqDecimal(env.token(USDC).balanceOf(address(vault)), 0, 6, "vault has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(vault)), 0, 18, "vault has ETH balance");

        assertEqDecimal(env.token(USDC).balanceOf(address(sut)), 0, 6, "strategy has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(sut)), 0, 18, "strategy has ETH balance");
    }

    function _open(uint256 cashflow, uint256 shortQty, uint256 longQty)
        internal
        returns (PositionId longPositionId, PositionId shortPositionId)
    {
        EIP2098Permit memory signedPermit = env.dealAndPermit2(shortInstrument.base, trader, traderPK, cashflow, address(sut));
        uint256 flashLoanAmount = shortQty - cashflow;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.base), flashLoanAmount);

        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.base, flashLoanAmount)));
        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(shortInstrument.base, signedPermit, cashflow, vault)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.base, shortQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(_shortPositionId, POSITION_TWO, shortQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, longQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(_longPositionId, POSITION_ONE, longQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_ONE, flashLoanAmount + flashLoanFee)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.base, flashLoanAmount + flashLoanFee)));

        vm.prank(trader);
        snapStart("SimpleFarmPosition:Open");
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
        assertApproxEqAbsDecimal(longBalances.debt, 5000e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 15_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function testIncreasePosition() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        // Treble the position
        uint256 cashflow = 20_000e6;
        EIP2098Permit memory signedPermit = env.dealAndPermit2(shortInstrument.base, trader, traderPK, cashflow, address(sut));

        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        uint256 shortQty = 30_000e6;
        uint256 longQty = 20 ether;
        uint256 flashLoanAmount = shortQty - cashflow;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.base), flashLoanAmount);

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.base, flashLoanAmount)));
        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(shortInstrument.base, signedPermit, cashflow, vault)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.base, shortQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(shortPositionId, POSITION_TWO, shortQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(shortPositionId, POSITION_TWO, longQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(longPositionId, POSITION_ONE, longQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(longPositionId, POSITION_ONE, flashLoanAmount + flashLoanFee)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.base, flashLoanAmount + flashLoanFee)));

        snapStart("SimpleFarmPosition:Increase");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 30 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 15_000e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 45_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 30 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function testRebalancePosition_LongToShort() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        // Rebalance the position
        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        uint256 rebalanceAmount = 1 ether;

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.PositionWithdraw, abi.encode(longPositionId, POSITION_ONE, rebalanceAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(shortPositionId, POSITION_TWO, rebalanceAmount)));

        snapStart("SimpleFarmPosition:RebalancePosition_LongToShort");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 9 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 5000e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 15_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 9 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function testRebalancePosition_ShortToLong() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        // Rebalance the position
        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        uint256 rebalanceAmount = 1 ether;

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(shortPositionId, POSITION_TWO, rebalanceAmount)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(longPositionId, POSITION_ONE, rebalanceAmount)));

        snapStart("SimpleFarmPosition:RebalancePosition_ShortToLong");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 11 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 5000e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 15_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 11 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function _stubNextAaveRates(TestInstrument memory instrument, uint128 baseRate, uint128 quoteRate) internal {
        IPool pool = env.aaveAddressProvider().getPool();

        vm.mockCall(pool.getReserveData(instrument.base).interestRateStrategyAddress, "", abi.encode(baseRate, 0, 0));
        vm.mockCall(pool.getReserveData(instrument.quote).interestRateStrategyAddress, "", abi.encode(0, 0, quoteRate));
    }

    function _stubNextRadiantRates(TestInstrument memory instrument, uint128 baseRate, uint128 quoteRate) internal {
        IPoolV2 pool = env.radiantAddressProvider().getLendingPool();

        vm.mockCall(address(pool.getReserveData(address(instrument.base)).interestRateStrategyAddress), "", abi.encode(baseRate, 0, 0));
        vm.mockCall(address(pool.getReserveData(address(instrument.quote)).interestRateStrategyAddress), "", abi.encode(0, 0, quoteRate));

        vm.mockCall(
            pool.getReserveData(address(instrument.quote)).variableDebtTokenAddress,
            abi.encodeWithSignature("burn(address,uint256,uint256)"),
            ""
        );
    }

    function testClose_LongCollateralBiggerThanShortDebt() public invariants {
        _stubNextAaveRates(longInstrument, 0.1e27, 0.2e27);
        _stubNextRadiantRates(shortInstrument, 0.5e27, 0.05e27);

        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        skip(365 days);
        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 11 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 6106.664668e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 22_499.999999e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10.512709087319861668 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        uint256 flashLoanAmount = shortBalances.debt * 1.001e18 / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.quote), flashLoanAmount);

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(shortPositionId, POSITION_TWO, flashLoanAmount)));
        steps.push(StepCall(Step.PositionClose, abi.encode(shortPositionId, POSITION_TWO)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(longPositionId, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(longPositionId, POSITION_ONE)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.quote, flashLoanAmount + flashLoanFee)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.base, sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.quote, sut.BALANCE(), trader)));

        snapStart("SimpleFarmPosition:Close_LongCollateralBiggerThanShortDebt");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(longPositionId), "longPositionId exists");
        assertFalse(positionNFT.exists(shortPositionId), "shortPositionId exists");

        assertApproxEqAbsDecimal(
            shortInstrument.base.balanceOf(trader),
            shortBalances.collateral - longBalances.debt,
            1,
            shortInstrument.baseDecimals,
            "quote cashflow"
        );
        assertApproxEqAbsDecimal(
            trader.balance, longBalances.collateral - shortBalances.debt, 1, shortInstrument.quoteDecimals, "base cashflow"
        );
    }

    function testClose_LongCollateralSmallerThanShortDebt() public invariants {
        _stubNextAaveRates(longInstrument, 0.05e27, 0.1e27);
        _stubNextRadiantRates(shortInstrument, 0.2e27, 0.1e27);

        (PositionId longPositionId, PositionId shortPositionId) = _open({ cashflow: 10_000e6, shortQty: 15_000e6, longQty: 10 ether });

        skip(365 days);
        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 10.5 ether, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 5525.810214e6, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 18_000e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 11.051672700152021886 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        FancySpot spot = new FancySpot();
        deal(address(shortInstrument.quote), address(spot), 0.6 ether);
        SwapData memory swapData = SwapData({
            router: address(spot),
            spender: address(spot),
            amountIn: 600e6,
            minAmountOut: 0.6 ether,
            swapBytes: abi.encodeWithSelector(spot.swap.selector, shortInstrument.base, 600e6, shortInstrument.quote, 0.6 ether)
        });

        uint256 flashLoanAmount = shortBalances.debt * 1.001e18 / WAD;
        uint256 flashLoanFee = flashLoanProvider.flashFee(address(shortInstrument.quote), flashLoanAmount);

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.TakeFlashloan, abi.encode(flashLoanProvider, shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.quote, flashLoanAmount)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(shortPositionId, POSITION_TWO, flashLoanAmount)));
        steps.push(StepCall(Step.PositionClose, abi.encode(shortPositionId, POSITION_TWO)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(longPositionId, POSITION_ONE, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(longPositionId, POSITION_ONE)));
        steps.push(StepCall(Step.SwapFromVault, abi.encode(swapData, shortInstrument.base, shortInstrument.quote)));
        steps.push(StepCall(Step.RepayFlashloan, abi.encode(shortInstrument.quote, flashLoanAmount + flashLoanFee)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.base, sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.quote, sut.BALANCE(), trader)));

        snapStart("SimpleFarmPosition:Close_LongCollateralSmallerThanShortDebt");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(longPositionId), "longPositionId exists");
        assertFalse(positionNFT.exists(shortPositionId), "shortPositionId exists");

        assertApproxEqAbsDecimal(
            shortInstrument.base.balanceOf(trader),
            shortBalances.collateral - longBalances.debt - 600e6,
            1,
            shortInstrument.baseDecimals,
            "quote cashflow"
        );
        assertApproxEqAbsDecimal(
            trader.balance, longBalances.collateral + 0.6 ether - shortBalances.debt, 1, shortInstrument.quoteDecimals, "base cashflow"
        );
    }

}

contract FancySpot {

    function swap(IERC20 sell, uint256 sellAmount, IERC20 buy, uint256 buyAmount) external {
        sell.transferFrom(msg.sender, address(this), sellAmount);
        buy.transfer(msg.sender, buyAmount);
    }

}

interface IReserveInterestRateStrategy {

    struct CalculateInterestRatesParams {
        uint256 unbacked;
        uint256 liquidityAdded;
        uint256 liquidityTaken;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 averageStableBorrowRate;
        uint256 reserveFactor;
        address reserve;
        address aToken;
    }

    function calculateInterestRates(CalculateInterestRatesParams memory params)
        external
        view
        returns (uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate);

}

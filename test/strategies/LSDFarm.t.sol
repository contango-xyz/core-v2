//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract LSDFarmTest is Test, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    Contango internal contango;
    ContangoLens internal lens;
    PositionNFT internal positionNFT;
    TestInstrument internal longInstrument;
    TestInstrument internal shortInstrument;
    PositionId internal _longPositionId;
    PositionId internal _shortPositionId;
    IERC7399 internal flashLoanProvider;
    SimpleSpotExecutor internal spotExecutor;
    IVault internal vault;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init(116_079_314);

        contango = env.contango();
        lens = env.contangoLens();
        positionNFT = env.positionNFT();
        vault = env.vault();
        flashLoanProvider = env.tsQuoter().flashLoanProviders(0);
        longInstrument = env.createInstrument(env.erc20(WSTETH), env.erc20(WETH));
        shortInstrument = env.createInstrument(env.erc20(USDC), env.erc20(WETH));
        (trader, traderPK) = makeAddrAndKey("trader");
        spotExecutor = env.maestro().spotExecutor();

        sut = env.strategyBuilder();

        address poolAddress = env.spotStub().stubPrice({
            base: longInstrument.baseData,
            quote: longInstrument.quoteData,
            baseUsdPrice: 1150e8,
            quoteUsdPrice: 1000e8,
            uniswapFee: 500
        });
        deal(address(longInstrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(longInstrument.quoteData.token), poolAddress, type(uint96).max);

        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
        stubChainlinkPrice(1.15e18, 0xe59EBa0D492cA53C6f46015EEa00517F2707dc77); // Lido: Chainlink wstETH-ETH exchange rate

        _longPositionId = encode(longInstrument.symbol, MM_AAVE, PERP, 0, flagsAndPayload(setBit("", E_MODE), bytes4(uint32(2))));
        _shortPositionId = env.encoder().encodePositionId(shortInstrument.symbol, MM_SONNE, PERP, 0);
    }

    modifier invariants() {
        _;

        assertEqDecimal(env.token(USDC).balanceOf(address(vault)), 0, 6, "vault has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(vault)), 0, 18, "vault has ETH balance");
        assertEqDecimal(env.token(WSTETH).balanceOf(address(vault)), 0, 18, "vault has WSTETH balance");

        assertEqDecimal(env.token(USDC).balanceOf(address(sut)), 0, 6, "strategy has USDC balance");
        assertEqDecimal(env.token(WETH).balanceOf(address(sut)), 0, 18, "strategy has ETH balance");
        assertEqDecimal(env.token(WSTETH).balanceOf(address(sut)), 0, 18, "strategy has WSTETH balance");
    }

    function _open(uint256 shortQty, uint256 longQty, uint256 longCashflow)
        internal
        returns (PositionId longPositionId, PositionId shortPositionId)
    {
        EIP2098Permit memory signedPermit = env.dealAndPermit2(shortInstrument.base, trader, traderPK, shortQty, address(sut));

        TSQuote memory quote = env.positionActions().quoteWithCashflow({
            positionId: _longPositionId,
            quantity: int256(longQty),
            cashflow: int256(longCashflow),
            cashflowCcy: Currency.Quote
        });

        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(shortInstrument.base, signedPermit, shortQty, vault)));
        steps.push(StepCall(Step.VaultDeposit, abi.encode(shortInstrument.base, shortQty)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(_shortPositionId, POSITION_TWO, shortQty)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_TWO, uint256(quote.cashflowUsed))));
        steps.push(StepCall(Step.Trade, abi.encode(POSITION_ONE, quote.tradeParams, quote.execParams)));

        vm.prank(trader);
        snapStart("LSDFarm:Open");
        StepResult[] memory results = sut.process(steps);
        snapEnd();

        shortPositionId = abi.decode(results[2].data, (PositionId));
        longPositionId = abi.decode(results[4].data, (PositionId));
    }

    function testOpen() public invariants {
        uint256 shortQty = 20_000e6;
        (PositionId longPositionId, PositionId shortPositionId) = _open({ shortQty: shortQty, longQty: 110e18, longCashflow: 10 ether });

        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(longBalances.collateral, 110e18, 1, longInstrument.baseDecimals, "longBalances.collateral");
        assertApproxEqAbsDecimal(longBalances.debt, 116.5 ether, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, shortQty, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        assertEq(positionNFT.positionOwner(longPositionId), trader, "longPositionId owner");
        assertEq(positionNFT.positionOwner(shortPositionId), trader, "shortPositionId owner");
    }

    function testClose() public invariants {
        (PositionId longPositionId, PositionId shortPositionId) = _open({ shortQty: 20_000e6, longQty: 110e18, longCashflow: 10 ether });

        skip(365 days);
        Balances memory longBalances = lens.balances(longPositionId);
        Balances memory shortBalances = lens.balances(shortPositionId);

        assertApproxEqAbsDecimal(
            longBalances.collateral, 110.009422337537754852e18, 1, longInstrument.baseDecimals, "longBalances.collateral"
        );
        assertApproxEqAbsDecimal(longBalances.debt, 119.165335891327421655e18, 1, longInstrument.quoteDecimals, "longBalances.debt");
        assertApproxEqAbsDecimal(shortBalances.collateral, 21_932.059282e6, 1, shortInstrument.baseDecimals, "shortBalances.collateral");
        assertApproxEqAbsDecimal(shortBalances.debt, 10.477152769016799995 ether, 1, shortInstrument.quoteDecimals, "shortBalances.debt");

        env.spotStub().stubPrice({
            base: longInstrument.baseData,
            quote: longInstrument.quoteData,
            baseUsdPrice: 1200e8,
            quoteUsdPrice: 1000e8,
            uniswapFee: 500
        });
        stubChainlinkPrice(1.2e18, 0xe59EBa0D492cA53C6f46015EEa00517F2707dc77); // Lido: Chainlink wstETH-ETH exchange rate

        PositionPermit memory longPermit = env.positionIdPermit2(longPositionId, trader, traderPK, address(sut));

        TSQuote memory quote = env.positionActions().quoteWithCashflow({
            positionId: longPositionId,
            quantity: type(int128).min,
            cashflow: -1,
            cashflowCcy: Currency.Quote
        });

        delete steps;
        steps.push(StepCall(Step.PullPosition, abi.encode(longPermit)));
        steps.push(StepCall(Step.Trade, abi.encode(POSITION_ONE, quote.tradeParams, quote.execParams)));
        steps.push(StepCall(Step.PositionRepay, abi.encode(shortPositionId, POSITION_TWO, sut.ALL())));
        steps.push(StepCall(Step.PositionClose, abi.encode(shortPositionId, POSITION_TWO)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.base, sut.BALANCE(), trader)));
        // steps.push(StepCall(Step.VaultWithdraw, abi.encode(shortInstrument.quote, sut.BALANCE(), trader)));

        snapStart("LSDFarm:Close");
        vm.prank(trader);
        positionNFT.safeTransferFrom(trader, address(sut), shortPositionId.asUint(), abi.encode(steps));
        snapEnd();

        assertFalse(positionNFT.exists(longPositionId), "longPositionId exists");
        assertFalse(positionNFT.exists(shortPositionId), "shortPositionId exists");

        assertApproxEqAbsDecimal(
            shortInstrument.base.balanceOf(trader), shortBalances.collateral, 1, shortInstrument.baseDecimals, "quote cashflow"
        );
        // 110.009422337537754852 * 1.2 - 119.165335891327421655 - 10.477152769016799995 = 2.3688181447
        assertApproxEqAbsDecimal(trader.balance, 2.36881814468577835 ether, 1, shortInstrument.quoteDecimals, "base cashflow");
    }

}

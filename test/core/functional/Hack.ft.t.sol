//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract Hacks is BaseTest {

    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    Contango internal contango;
    IVault internal vault;

    Trade internal expectedTrade;
    uint256 internal expectedCollateral;
    uint256 internal expectedDebt;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        contango = env.contango();
        vault = env.vault();

        mm = MM_AAVE;
        instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(1e6);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testStealFromAnotherPosition() public {
        (, PositionId positionId1,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (, PositionId positionId2,) = env.positionActions2().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances1 = env.contangoLens().balances(positionId1);
        assertApproxEqAbsDecimal(balances1.collateral, 9.99 ether, 0.001 ether, instrument.baseDecimals, "collateral 1");
        assertApproxEqAbsDecimal(balances1.debt, 6000e6, 1e6, instrument.quoteDecimals, "debt 1");

        Balances memory balances2 = env.contangoLens().balances(positionId2);
        assertApproxEqAbsDecimal(balances2.collateral, 9.99 ether, 0.001 ether, instrument.baseDecimals, "collateral 2");
        assertApproxEqAbsDecimal(balances2.debt, 6000e6, 1e6, instrument.quoteDecimals, "debt 2");

        IERC20 weth = env.token(WETH);

        IMoneyMarket victimsAccount = contango.positionFactory().moneyMarket(positionId1);
        uint256 baseToSteal = 1 ether;

        // function withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to) external returns (uint256 actualAmount);
        bytes memory hackBytes = abi.encodeWithSelector(IMoneyMarket.withdraw.selector, positionId1, weth, baseToSteal, contango);

        env.dealAndApprove(weth, TRADER2, 1, address(vault));
        vm.prank(TRADER2);
        vault.depositTo(weth, TRADER2, 1);

        // Let's steal from position 1
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, env.contango().spotExecutor()));
        vm.prank(TRADER2);
        contango.trade(
            TradeParams({
                positionId: positionId2,
                quantity: 1 ether,
                cashflow: 0,
                cashflowCcy: Currency.None,
                limitPrice: 0 // Any price is fine
             }),
            ExecutionParams({
                router: address(victimsAccount),
                spender: address(victimsAccount),
                swapAmount: 1, // Doesn't matter
                swapBytes: hackBytes,
                flashLoanProvider: IERC7399(address(0)) // Doesn't matter
             })
        );

        // status1 = env.quoter().positionStatus(positionId1);
        // assertEqDecimal(status1.collateral, 8.980019980019980018 ether, instrument.baseDecimals, "collateral 1");
        // assertEqDecimal(status1.debt, 6000e6, instrument.quoteDecimals, "debt 1");

        // status2 = env.quoter().positionStatus(positionId2);
        // assertEqDecimal(status2.collateral, 10.979019980019980018 ether, instrument.baseDecimals, "collateral 2");
        // assertEqDecimal(status2.debt, 6000.000001e6, instrument.quoteDecimals, "debt 2");
    }

}

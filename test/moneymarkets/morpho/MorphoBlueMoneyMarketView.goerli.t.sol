//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

contract MorphoBlueMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using MarketParamsLib for MarketParams;

    Env internal env;
    MorphoBlueMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    IMorpho internal morpho;
    MorphoBlueReverseLookup internal reverseLookup;

    MoneyMarketId internal constant mmId = MM_MORPHO_BLUE;

    Payload internal payload;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    function setUp() public {
        env = provider(Network.Goerli);
        env.init();

        contango = env.contango();
        morpho = env.morpho();

        // Hack until they deploy the final version
        vm.etch(address(morpho), vm.getDeployedCode("Morpho.sol"));

        MorphoBlueMoneyMarket mm = MorphoBlueMoneyMarket(address(env.positionFactory().moneyMarket(mmId)));
        reverseLookup = mm.reverseLookup();

        sut = new MorphoBlueMoneyMarketView(mmId, env.positionFactory(), morpho, reverseLookup);

        MorphoOracleMock oracle = new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC));
        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: oracle,
            irm: IIrm(0x2056d9E6E323Fd06f4344c35022B19849C6402B3),
            lltv: 0.9e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.prank(Timelock.unwrap(TIMELOCK));
        payload = reverseLookup.setMarket(params.id());

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = encode(instrument.symbol, mmId, PERP, 0, payload);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
        deal(address(instrument.quoteData.token), env.balancer(), type(uint96).max);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId, instrument.base, instrument.quote);

        assertApproxEqRelDecimal(balances.collateral, 10 ether, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 6000e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public {
        Prices memory prices = sut.prices(positionId, instrument.base, instrument.quote);

        assertEqDecimal(prices.collateral, 1000e24, 24, "Collateral price");
        assertEqDecimal(prices.debt, 1e24, 24, "Debt price");
        assertEq(prices.unit, 1e24, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 afterPosition,) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(beforePosition, 100_000e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 6000e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public {
        (, uint256 liq) = sut.liquidity(positionId, instrument.base, instrument.quote);

        assertEqDecimal(liq, instrument.base.totalSupply(), instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.9e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.9e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId, instrument.base, instrument.quote);

        assertEqDecimal(ltv, 0.9e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.9e18, 18, "Liquidation threshold");
    }

    function testRates() public {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId, instrument.base, instrument.quote);

        assertEqDecimal(borrowingRate, 0.000000000317097919e18, 18, "Borrowing rate");
        assertEq(lendingRate, 0, "Lending rate");
    }

}

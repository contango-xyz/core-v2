//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

contract MorphoBlueMoneyMarketViewTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using MarketParamsLib for MarketParams;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    IMorpho internal morpho;
    MorphoBlueReverseLookup internal reverseLookup;

    MoneyMarketId internal constant mmId = MM_MORPHO_BLUE;

    Payload internal payload;

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.0022e18;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_941_334);

        contango = env.contango();
        morpho = env.morpho();

        MorphoBlueMoneyMarket mm = MorphoBlueMoneyMarket(address(env.positionFactory().moneyMarket(mmId)));
        reverseLookup = mm.reverseLookup();

        sut = env.contangoLens().moneyMarketView(mmId);

        instrument = env.createInstrument(env.erc20(WSTETH), env.erc20(USDC));

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        payload = reverseLookup.setMarket(MorphoMarketId.wrap(0xB323495F7E4148BE5643A4EA4A8221EEF163E4BCCFDEDC2A6F4696BAACBC86CC)); // WSTETH/USDC
        vm.stopPrank();

        stubChainlinkPrice(1.15e8, 0x4F67e4d9BD67eFa28236013288737D39AeF48e79); // WSTETH/ETH
        stubChainlinkPrice(0.001e18, CHAINLINK_USDC_ETH); // USDC/ETH
        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle)); // ETH/USD
        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1150e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        positionId = encode(instrument.symbol, mmId, PERP, 0, payload);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function testBalances_NewPosition() public {
        Balances memory balances = sut.balances(positionId);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition() public {
        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 1e18, cashflow: 600e6, cashflowCcy: Currency.Quote });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(balances.collateral, 1e18, TOLERANCE, instrument.baseDecimals, "Collateral balance");
        assertApproxEqRelDecimal(balances.debt, 550e6, TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testPrices() public view {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, 1150e24, 24, "Collateral price");
        assertEqDecimal(prices.debt, 1e24, 24, "Debt price");
        assertEq(prices.unit, 1e24, "Oracle Unit");
    }

    function testBorrowingLiquidity() public {
        (uint256 beforePosition,) = sut.liquidity(positionId);

        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 1e18, cashflow: 600e6, cashflowCcy: Currency.Quote });

        (uint256 afterPosition,) = sut.liquidity(positionId);

        assertEqDecimal(beforePosition, 1090e6, instrument.quoteDecimals, "Borrowing liquidity");
        assertApproxEqRelDecimal(beforePosition - afterPosition, 550e6, TOLERANCE, instrument.quoteDecimals, "Borrowing liquidity delta");
    }

    function testLendingLiquidity() public view {
        (, uint256 liq) = sut.liquidity(positionId);

        assertEqDecimal(liq, instrument.base.totalSupply(), instrument.baseDecimals, "Lending liquidity");
    }

    function testThresholds_NewPosition() public view {
        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.86e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition() public {
        (, positionId,) =
            env.positionActions().openPosition({ positionId: positionId, quantity: 1e18, cashflow: 200e6, cashflowCcy: Currency.Quote });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.86e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.86e18, 18, "Liquidation threshold");
    }

    function testRates() public view {
        (uint256 borrowingRate, uint256 lendingRate) = sut.rates(positionId);

        assertEqDecimal(borrowingRate, 0.008011868665814026e18, 18, "Borrowing rate");
        assertEq(lendingRate, 0, "Lending rate");
    }

}

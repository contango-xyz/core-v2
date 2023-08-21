//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../../BaseTest.sol";

/// @dev scenario implementation for https://docs.google.com/spreadsheets/d/1jbb2yy9RfumOwdd6UTo4fzx0Z28FJ-GiRFGN6DKeE9Q/edit#gid=0
contract EModeTest is BaseTest {

    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarket internal mm;
    UniswapPoolStub internal poolStub;

    Trade internal expectedTrade;
    uint256 internal expectedCollateral;
    uint256 internal expectedDebt;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();

        env.positionActions().setSlippageTolerance(0);

        mm = MM_AAVE;
        instrument = env.createInstrument({ baseData: env.erc20(DAI), quoteData: env.erc20(USDC) });

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 3000
        });

        env.etchNoFeeModel();

        poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(0);

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
        deal(address(instrument.baseData.token), env.balancer(), type(uint96).max);
    }

    function testOpenEModePosition() public {
        uint256 leverage = 14e18;

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            leverage: leverage,
            cashflow: 10_000e6,
            cashflowCcy: Currency.Quote
        });

        OracleData memory oracleData = env.quoter().positionStatus(positionId).oracleData;

        console.log("collateral %s, debt %s, unit %s", oracleData.collateral, oracleData.debt, oracleData.unit);

        uint256 margin = (oracleData.collateral - oracleData.debt) * oracleData.unit / oracleData.collateral;
        uint256 actual = 1e18 * oracleData.unit / margin;

        console.log("margin %s, leverage %s", margin, actual);
        assertApproxEqRelDecimal(actual, leverage, 0.00001e18, 18, "leverage");
    }

}

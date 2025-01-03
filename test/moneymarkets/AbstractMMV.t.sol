//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";
import "./utils.t.sol";

contract AbstractMarketViewTest is Test {

    using { enabled } for AvailableActions[];

    // Fees are 0.1% so the numbers are slightly off
    uint256 internal constant TOLERANCE = 0.002e18;

    Env internal env;
    IMoneyMarketView internal sut;
    PositionId internal positionId;
    Contango internal contango;
    TestInstrument internal instrument;
    uint256 internal baseUsdPrice;
    uint256 internal quoteUsdPrice;
    uint256 internal oracleDecimals;

    MoneyMarketId internal immutable mm;

    constructor(MoneyMarketId _mm) {
        mm = _mm;
    }

    function setUp(Network network) internal virtual {
        setUp(network, forkBlock(network), WETH, 1000e8, USDC, 1e8, 8);
    }

    function setUp(Network network, uint256 blockNo) internal virtual {
        setUp(network, blockNo, WETH, 1000e8, USDC, 1e8, 8);
    }

    function setUp(
        Network network,
        uint256 blockNo,
        bytes32 base,
        uint256 _baseUsdPrice,
        bytes32 quote,
        uint256 _quoteUsdPrice,
        uint256 _oracleDecimals
    ) internal virtual {
        baseUsdPrice = _baseUsdPrice;
        quoteUsdPrice = _quoteUsdPrice;
        oracleDecimals = _oracleDecimals;

        env = provider(network);
        env.init(blockNo);

        contango = env.contango();
        sut = env.contangoLens().moneyMarketView(mm);

        instrument = env.createInstrument(env.erc20(base), env.erc20(quote));

        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: int256(baseUsdPrice),
            quoteUsdPrice: int256(quoteUsdPrice),
            uniswapFee: 500
        });

        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
    }

    function _baseTestQty() internal view virtual returns (uint256) {
        return 10;
    }

    function _basePrecision(uint256 x) internal view virtual returns (uint256) {
        return x * instrument.baseUnit;
    }

    function _quoteTestQty() internal view virtual returns (uint256) {
        return 4000;
    }

    function _quotePrecision(uint256 x) internal view virtual returns (uint256) {
        return x * instrument.quoteUnit;
    }

    function _expectedDebt() internal view virtual returns (uint256) {
        return 6000;
    }

    function _oraclePrecision(uint256 x) internal view virtual returns (uint256) {
        return x * 10 ** oracleDecimals;
    }

    function _wadPrecision(uint256 x) internal pure virtual returns (uint256) {
        return x * WAD;
    }

    function _transformPrecision(uint256 x, uint256 from, uint256 to) internal pure virtual returns (uint256) {
        if (to > from) return x * 10 ** (to - from);
        else return x / 10 ** (from - to);
    }

    function testBalances_NewPosition() public virtual {
        Balances memory balances = sut.balances(positionId);
        assertEqDecimal(balances.collateral, 0, instrument.baseDecimals, "Collateral balance");
        assertEqDecimal(balances.debt, 0, instrument.quoteDecimals, "Debt balance");
    }

    function testBalances_ExistingPosition() public virtual {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: _basePrecision(_baseTestQty()),
            cashflow: int256(_quotePrecision(_quoteTestQty())),
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balances(positionId);

        assertApproxEqRelDecimal(
            balances.collateral, _basePrecision(_baseTestQty()), TOLERANCE, instrument.baseDecimals, "Collateral balance"
        );
        assertApproxEqRelDecimal(balances.debt, _quotePrecision(_expectedDebt()), TOLERANCE, instrument.quoteDecimals, "Debt balance");
    }

    function testBalancesUSD() public virtual {
        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: _basePrecision(_baseTestQty()),
            cashflow: int256(_quotePrecision(_quoteTestQty())),
            cashflowCcy: Currency.Quote
        });

        Balances memory balances = sut.balancesUSD(positionId);

        assertApproxEqRelDecimal(
            balances.collateral, _transformPrecision(_baseTestQty() * baseUsdPrice, oracleDecimals, 18), TOLERANCE, 18, "Collateral balance"
        );
        assertApproxEqRelDecimal(
            balances.debt, _transformPrecision(_expectedDebt() * quoteUsdPrice, oracleDecimals, 18), TOLERANCE, 18, "Debt balance"
        );
    }

    function testPrices() public virtual {
        Prices memory prices = sut.prices(positionId);

        assertEqDecimal(prices.collateral, _transformPrecision(baseUsdPrice, 8, oracleDecimals), oracleDecimals, "Collateral price");
        assertEqDecimal(prices.debt, _transformPrecision(quoteUsdPrice, 8, oracleDecimals), oracleDecimals, "Debt price");
        assertEq(prices.unit, 10 ** oracleDecimals, "Oracle Unit");
    }

    function testPriceInUSD() public virtual {
        assertApproxEqAbsDecimal(
            sut.priceInUSD(instrument.base), _transformPrecision(baseUsdPrice, oracleDecimals, 18), 1, 18, "Base price in USD"
        );
        assertApproxEqAbsDecimal(
            sut.priceInUSD(instrument.quote), _transformPrecision(quoteUsdPrice, oracleDecimals, 18), 1, 18, "Quote price in USD"
        );
    }

    function testBaseQuoteRate() public virtual {
        uint256 baseQuoteRate = sut.baseQuoteRate(positionId);
        assertEqDecimal(
            baseQuoteRate, _transformPrecision(baseUsdPrice, 8, instrument.quoteDecimals), instrument.quoteDecimals, "Base quote rate"
        );
    }

    function testAvailableActions_HappyPath() public virtual {
        AvailableActions[] memory availableActions = sut.availableActions(positionId);

        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_ClosingOnly() public virtual {
        vm.prank(TIMELOCK_ADDRESS);
        contango.grantRole(OPERATOR_ROLE, address(this));

        contango.setClosingOnly(instrument.symbol, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);

        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_Paused() public virtual {
        vm.prank(TIMELOCK_ADDRESS);
        contango.grantRole(EMERGENCY_BREAK_ROLE, address(this));

        contango.pause();

        assertEq(sut.availableActions(positionId).length, 0, "Everything is disabled");
    }

    function testLimits() public virtual {
        Limits memory limits = sut.limits(positionId);

        assertEqDecimal(limits.minBorrowing, 0, instrument.quoteDecimals, "Min borrowing");
        assertEqDecimal(limits.maxBorrowing, type(uint256).max, instrument.quoteDecimals, "Max borrowing");
        assertEqDecimal(limits.minBorrowingForRewards, 0, instrument.quoteDecimals, "Min borrowing for rewards");
        assertEqDecimal(limits.minLending, 0, instrument.baseDecimals, "Min lending");
        assertEqDecimal(limits.maxLending, type(uint256).max, instrument.baseDecimals, "Max lending");
        assertEqDecimal(limits.minLendingForRewards, 0, instrument.baseDecimals, "Min lending for rewards");
    }

    function testIrmRaw() public virtual {
        sut.irmRaw(positionId);
    }

}

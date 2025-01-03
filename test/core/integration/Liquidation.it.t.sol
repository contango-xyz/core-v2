//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";
import "src/moneymarkets/Liquidations.sol";
import "../../utils.t.sol";

abstract contract Liquidation is BaseTest, Liquidations {

    using Math for *;
    using SignedMath for *;

    Env internal env;
    TestInstrument internal instrument;
    MoneyMarketId internal mm;
    UniswapPoolStub internal poolStub;
    ContangoLens internal lens;
    IUnderlyingPositionFactory internal positionFactory;

    PositionId internal positionId;
    address internal liquidator = makeAddr("liquidator");

    function ADDRESSES_PROVIDER() external pure override returns (address) {
        return address(0);
    }

    function getConfiguration(address) external pure override returns (ReserveConfigurationMap memory) {
        return ReserveConfigurationMap({ data: 0 });
    }

    function setUp(Network network, MoneyMarketId _mm, bytes32 base, bytes32 quote) internal virtual {
        setUp(network, forkBlock(network), _mm, base, quote);
    }

    function setUp(Network network, uint256 blockNo, MoneyMarketId _mm, bytes32 base, bytes32 quote) internal virtual {
        env = provider(network);
        env.init(blockNo);
        lens = env.contangoLens();
        positionFactory = env.positionFactory();

        mm = _mm;
        instrument = env.createInstrument({ baseData: env.erc20(base), quoteData: env.erc20(quote) });

        // go around rounding issues when calculating price from swap data
        env.positionActions().setSlippageTolerance(DEFAULT_SLIPPAGE_TOLERANCE + 1);

        address poolAddress = env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        poolStub = UniswapPoolStub(poolAddress);
        poolStub.setAbsoluteSpread(int256(0));

        deal(address(instrument.baseData.token), poolAddress, type(uint96).max);
        deal(address(instrument.quoteData.token), poolAddress, type(uint96).max);
    }

    function _movePrice(int256 percentage) internal virtual {
        env.spotStub().movePrice(instrument.baseData, percentage);
    }

}

abstract contract AbstractAaveV3Liquidation is Liquidation {

    using { first } for Vm.Log[];
    using { asAddress } for bytes32;

    function test_Liquidate() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 0,
            cashflowCcy: Currency.Quote
        });

        _movePrice(-0.05e18);

        address account = address(positionFactory.moneyMarket(positionId));
        IPool pool = AaveMoneyMarket(account).pool();
        uint256 debtToCover = lens.balances(positionId).debt / 2;
        env.dealAndApprove(instrument.quote, liquidator, debtToCover, address(pool));

        vm.recordLogs();
        vm.prank(liquidator);
        pool.liquidationCall(instrument.base, instrument.quote, account, debtToCover, false);

        Vm.Log memory log = vm.getRecordedLogs().first("LiquidationCall(address,address,address,uint256,uint256,address,bool)");
        assertEq(log.topics[1].asAddress(), address(instrument.base), "LiquidationCall.collateralAsset");
        assertEq(log.topics[2].asAddress(), address(instrument.quote), "OrderExecuted.debtAsset");
        assertEq(log.topics[3].asAddress(), account, "OrderExecuted.user");
    }

}

contract AaveV3Liquidation is AbstractAaveV3Liquidation {

    function setUp() public {
        setUp(Network.Arbitrum, MM_AAVE, WETH, USDC);
    }

}

contract SparkLiquidation is AbstractAaveV3Liquidation {

    function setUp() public {
        setUp(Network.Mainnet, 18_233_968, MM_SPARK_SKY, WETH, DAI);
    }

}

abstract contract AbstractAaveV2Liquidation is Liquidation {

    using { first } for Vm.Log[];
    using { asAddress } for bytes32;

    bytes internal eventSignature = "LiquidationCall(address,address,address,uint256,uint256,address,bool)";

    function test_Liquidate() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 0,
            cashflowCcy: Currency.Quote
        });

        _movePrice(-0.1e18);

        address account = address(positionFactory.moneyMarket(positionId));
        IPoolV2 pool = AaveV2MoneyMarket(account).poolV2();
        uint256 debtToCover = lens.balances(positionId).debt / 2;
        env.dealAndApprove(instrument.quote, liquidator, debtToCover, address(pool));

        vm.recordLogs();
        vm.prank(liquidator);
        pool.liquidationCall(instrument.base, instrument.quote, account, debtToCover, false);

        Vm.Log memory log = vm.getRecordedLogs().first(eventSignature);
        assertEq(log.topics[1].asAddress(), address(instrument.base), "LiquidationCall.collateralAsset");
        assertEq(log.topics[2].asAddress(), address(instrument.quote), "OrderExecuted.debtAsset");
        assertEq(log.topics[3].asAddress(), account, "OrderExecuted.user");
    }

}

// contract AgaveLiquidation is AbstractAaveV2Liquidation {

//     function setUp() public {
//         super.setUp(Network.Gnosis, MM_AGAVE, WETH, DAI);
//         eventSignature = "LiquidationCall(address,address,address,uint256,uint256,address,bool,bool)";
//     }

// }

contract RadiantLiquidation is AbstractAaveV2Liquidation {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_RADIANT, WETH, DAI);
        eventSignature = "LiquidationCall(address,address,address,uint256,uint256,address,bool,address)";
    }

}

abstract contract AbstractCompoundV2Liquidation is Liquidation {

    using { first } for Vm.Log[];
    using { asAddress } for bytes32;

    int256 internal cashflow;

    function setUp(Network network, MoneyMarketId _mm, bytes32 base, bytes32 quote, int256 _cashflow) internal virtual {
        setUp(network, forkBlock(network), _mm, base, quote, _cashflow);
    }

    function setUp(Network network, uint256 blockNo, MoneyMarketId _mm, bytes32 base, bytes32 quote, int256 _cashflow) internal virtual {
        super.setUp(network, blockNo, _mm, base, quote);
        cashflow = _cashflow;
    }

    function test_Liquidate() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: cashflow,
            cashflowCcy: Currency.Quote
        });

        _movePrice(-0.1e18);

        address account = address(positionFactory.moneyMarket(positionId));
        ICToken collateralCToken = CompoundMoneyMarket(payable(account)).cToken(instrument.base);
        ICToken debtCToken = CompoundMoneyMarket(payable(account)).cToken(instrument.quote);
        uint256 debtToCover = lens.balances(positionId).debt / 2;
        env.dealAndApprove(instrument.quote, liquidator, debtToCover, address(debtCToken));

        vm.recordLogs();
        vm.prank(liquidator);
        debtCToken.liquidateBorrow(account, debtToCover, collateralCToken);

        Vm.Log memory log = vm.getRecordedLogs().first("LiquidateBorrow(address,address,uint256,address,uint256)");
        (address liquidator, address borrower, uint256 repayAmount, address cTokenCollateral) =
            abi.decode(log.data, (address, address, uint256, address));
        assertEq(liquidator, address(liquidator), "LiquidateBorrow.liquidator");
        assertEq(borrower, account, "LiquidateBorrow.borrower");
        assertEq(repayAmount, debtToCover, "LiquidateBorrow.repayAmount");
        assertEq(cTokenCollateral, address(collateralCToken), "LiquidateBorrow.cTokenCollateral");
    }

}

contract CompoundV2Liquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Mainnet, MM_COMPOUND, WETH, DAI, 1751e18);

        address oracle = env.compoundComptroller().oracle();
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(1000e18)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643),
            abi.encode(1e18)
        );
    }

    function _movePrice(int256 percentage) internal override {
        vm.mockCall(
            env.compoundComptroller().oracle(),
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(1000e18 * (percentage + 1e18) / 1e18)
        );
    }

}

contract LodestarLiquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Arbitrum, 152_284_580, MM_LODESTAR, WETH, USDC, 2001e6);
    }

}

contract MoonwellLiquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Base, MM_MOONWELL, WETH, USDC, 2001e6);
    }

}

contract EulerLiquidation is Liquidation {

    using { first } for Vm.Log[];
    using { asAddress } for bytes32;

    IEulerVault public ethVault = IEulerVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2);
    IEulerVault public usdcVault = IEulerVault(0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9);

    function setUp() public {
        super.setUp(Network.Mainnet, 20_678_328, MM_EULER, WETH, USDC);

        Contango contango = env.contango();

        EulerMoneyMarket mm = EulerMoneyMarket(address(contango.positionFactory().moneyMarket(MM_EULER)));

        vm.startPrank(TIMELOCK_ADDRESS);
        uint16 ethId = mm.reverseLookup().setVault(ethVault);
        uint16 usdcId = mm.reverseLookup().setVault(usdcVault);
        vm.stopPrank();

        env.encoder().setPayload(baseQuotePayload(ethId, usdcId));

        env.dealAndApprove(instrument.base, liquidator, 100 ether, address(ethVault));
        vm.startPrank(liquidator);
        mm.evc().enableController(liquidator, usdcVault);
        mm.evc().enableCollateral(liquidator, ethVault);
        ethVault.deposit(100 ether, liquidator);
        vm.stopPrank();
    }

    function test_Liquidate() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 2101e6,
            cashflowCcy: Currency.Quote
        });

        _movePrice(-0.05e18);
        skip(usdcVault.liquidationCoolOffTime() + 1);

        address account = address(positionFactory.moneyMarket(positionId));
        (uint256 maxRepay, uint256 maxYield) = usdcVault.checkLiquidation(liquidator, account, ethVault);
        assertGt(maxRepay, 0, "maxRepay");

        vm.recordLogs();
        vm.prank(liquidator);
        usdcVault.liquidate(account, ethVault, maxRepay, 0);

        // Liquidate(address indexed liquidator, address indexed violator, address collateral, uint256 repayAssets, uint256 yieldBalance)
        Vm.Log memory log = vm.getRecordedLogs().first("Liquidate(address,address,address,uint256,uint256)");
        assertEq(log.topics[1].asAddress(), liquidator, "Liquidate.liquidator");
        assertEq(log.topics[2].asAddress(), account, "Liquidate.violator");

        (address collateral, uint256 repayAssets, uint256 yieldBalance) = abi.decode(log.data, (address, uint256, uint256));
        assertEq(collateral, address(ethVault), "Liquidate.collateral");
        assertEq(repayAssets, maxRepay, "Liquidate.repayAssets");
        assertEq(yieldBalance, maxYield, "Liquidate.yieldBalance");
    }

}

contract FluidLiquidation is Liquidation {

    using { first, all } for Vm.Log[];
    using { asAddress } for bytes32;

    address oracle = CHAINLINK_USDC_ETH;

    function setUp() public {
        super.setUp(Network.Mainnet, 20_714_207, MM_FLUID, WETH, USDC);
        env.encoder().setPayload(Payload.wrap(bytes5(uint40(11))));
        stubChainlinkPrice(0.001e18, oracle);
    }

    function test_Liquidate() public {
        (, positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: mm,
            quantity: 10 ether,
            cashflow: 1500e6,
            cashflowCcy: Currency.Quote
        });

        env.spotStub().movePrice(oracle, "USDC", -0.05e18);

        FluidMoneyMarket account = FluidMoneyMarket(payable(address(positionFactory.moneyMarket(positionId))));
        IFluidVault vault = account.vault(positionId);

        uint256 debtToCover = 1000e6;
        env.dealAndApprove(instrument.quote, liquidator, debtToCover, address(vault));

        vm.recordLogs();
        vm.prank(liquidator);
        vault.liquidate(debtToCover, 0, liquidator, true);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory opeations = logs.all("LogOperate(address,address,int256,int256,address,address,uint256,uint256)");
        assertEq(opeations.length, 2, "LogOperate");

        Vm.Log memory log = opeations[0];
        assertEq(log.topics[1].asAddress(), address(vault), "LogOperate1.user");
        assertEq(log.topics[2].asAddress(), address(instrument.quote), "LogOperate1.token");

        (int256 supplyAmount, int256 borrowAmount) = abi.decode(log.data, (int256, int256));
        assertApproxEqAbsDecimal(supplyAmount, 0, 0, 0, "LogOperate1.supplyAmount");
        assertApproxEqAbsDecimal(borrowAmount, -int256(debtToCover), 1, 6, "LogOperate1.borrowAmount");

        log = opeations[1];
        assertEq(log.topics[1].asAddress(), address(vault), "LogOperate2.user");
        assertEq(log.topics[2].asAddress(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, "LogOperate2.token");

        (supplyAmount, borrowAmount) = abi.decode(log.data, (int256, int256));
        assertApproxEqAbsDecimal(supplyAmount, -0.63 ether, 0.001 ether, 18, "LogOperate2.supplyAmount");
        assertApproxEqAbsDecimal(borrowAmount, 0, 0, 0, "LogOperate2.borrowAmount");

        log = logs.first("LogLiquidate(address,uint256,uint256,address)");
        (address liquidator) = abi.decode(log.data, (address));
        assertEq(liquidator, liquidator, "LogLiquidate.liquidator");
    }

}

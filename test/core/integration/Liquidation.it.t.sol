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
        setUp(Network.Mainnet, 18_233_968, MM_SPARK, WETH, DAI);
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

contract AaveV2Liquidation is AbstractAaveV2Liquidation {

    function setUp() public {
        setUp(Network.Mainnet, MM_AAVE_V2, WETH, USDC);
        stubChainlinkPrice(0.001e18, 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
    }

    function _movePrice(int256 percentage) internal override {
        env.spotStub().movePrice(0x986b5E1e1755e3C2440e960477f25201B0a8bbD4, "USDC/ETH", -percentage);
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

contract GranaryLiquidation is AbstractAaveV2Liquidation {

    function setUp() public {
        super.setUp(Network.Optimism, MM_GRANARY, WETH, USDC);
    }

}

abstract contract AbstractCompoundV2Liquidation is Liquidation {

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
        super.setUp(Network.Mainnet, MM_COMPOUND, WETH, DAI);

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

contract SonneLiquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Optimism, MM_SONNE, WETH, DAI);
    }

}

contract LodestarLiquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Arbitrum, 152_284_580, MM_LODESTAR, WETH, USDC);
    }

}

contract MoonwellLiquidation is AbstractCompoundV2Liquidation {

    function setUp() public {
        super.setUp(Network.Base, MM_MOONWELL, WETH, USDC);
    }

}

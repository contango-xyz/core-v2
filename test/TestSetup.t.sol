// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "src/core/Contango.sol";
import "src/core/OrderManager.sol";
import "src/core/Maestro.sol";
import "src/core/Vault.sol";
import "src/dependencies/IWETH9.sol";
import "src/interfaces/IOrderManager.sol";

import "test/flp/TestFLP.sol";

import "src/moneymarkets/UnderlyingPositionFactory.sol";
import "src/moneymarkets/UpgradeableBeaconWithOwner.sol";
import "src/moneymarkets/ImmutableBeaconProxy.sol";
import "src/moneymarkets/aave/AaveMoneyMarket.sol";
import "src/moneymarkets/aave/AaveV2MoneyMarket.sol";
import "src/moneymarkets/aave/AaveV2MoneyMarketView.sol";
import "src/moneymarkets/aave/AaveMoneyMarketView.sol";
import "src/moneymarkets/aave/dependencies/IPoolAddressesProvider.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarket.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarketView.sol";
import "src/moneymarkets/compound/CompoundMoneyMarket.sol";
import "src/moneymarkets/compound/CompoundMoneyMarketView.sol";
import "src/moneymarkets/compound/SonneMoneyMarketView.sol";
import "src/moneymarkets/compound/LodestarMoneyMarketView.sol";
import "src/moneymarkets/comet/CometMoneyMarket.sol";
import "src/moneymarkets/comet/CometMoneyMarketView.sol";
import "src/moneymarkets/compound/MoonwellMoneyMarket.sol";
import "src/moneymarkets/compound/MoonwellMoneyMarketView.sol";
import "src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol";
import "src/moneymarkets/morpho/MorphoBlueMoneyMarketView.sol";
import "src/moneymarkets/silo/SiloMoneyMarket.sol";
import "src/moneymarkets/silo/SiloMoneyMarketView.sol";
import "src/moneymarkets/dolomite/DolomiteMoneyMarket.sol";
import "src/moneymarkets/dolomite/DolomiteMoneyMarketView.sol";
import "src/moneymarkets/euler/EulerMoneyMarket.sol";
import "src/moneymarkets/euler/EulerMoneyMarketView.sol";
import "src/moneymarkets/fluid/FluidMoneyMarket.sol";
import "src/moneymarkets/fluid/FluidMoneyMarketView.sol";
import "src/moneymarkets/ContangoLens.sol";
import "@contango/erc721Permit2/ERC721Permit2.sol";
import "src/strategies/PositionPermit.sol";
import "src/strategies/StrategyBuilder.sol";

import "script/constants.sol";
import "script/Addresses.s.sol";

import "src/dependencies/Chainlink.sol";
import "./dependencies/Uniswap.sol";
import "./dependencies/Aave.sol";
import { PositionActions } from "./PositionActions.sol";
import "./Encoder.sol";
import "./SpotStub.sol";
import "./PermitUtils.t.sol";
import "./Network.sol";
import "./utils.t.sol";
import "./TSQuoter.sol";
import { ERC20Mock } from "./stub/ERC20Mock.sol";

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

uint256 constant TRADER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
address payable constant TRADER = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
uint256 constant TRADER2_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
address payable constant TRADER2 = payable(address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8));
address payable constant LIQUIDATOR = payable(address(0xfec));

// erc20 tokens
bytes32 constant LINK = "LINK";
bytes32 constant DAI = "DAI";
bytes32 constant SDAI = "sDAI";
bytes32 constant USDC = "USDC";
bytes32 constant USDCn = "USDCn";
bytes32 constant WETH = "WETH";
bytes32 constant WMATIC = "WMATIC";
bytes32 constant WBTC = "WBTC";
bytes32 constant USDT = "USDT";
bytes32 constant ARB = "ARB";
bytes32 constant LUSD = "LUSD";
bytes32 constant RETH = "RETH";
bytes32 constant GNO = "GNO";
bytes32 constant WSTETH = "WSTETH";
bytes32 constant PTweETH27JUN2024 = "PTweETH27JUN2024";
bytes32 constant PENDLE = "PENDLE";
bytes32 constant WBNB = "WBNB";

uint256 constant DEFAULT_TRADING_FEE = 0.001e18; // 0.1%
uint256 constant DEFAULT_ORACLE_UNIT = 1e8;

bytes32 constant DEFAULT_ADMIN_ROLE = "";

Symbol constant WETHUSDC = Symbol.wrap("WETHUSDC");

address constant CHAINLINK_USDC_ETH = 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4;

function _deployCode(string memory what) returns (address addr) {
    bytes memory bytecode = VM.getCode(what);
    /// @solidity memory-safe-assembly
    assembly {
        addr := create(0, add(bytecode, 0x20), mload(bytecode))
    }

    require(addr != address(0), "_deployCode(string): Deployment failed.");
}

function provider(Network network) returns (Env) {
    if (network == Network.Arbitrum) return Env(_deployCode("TestSetup.t.sol:ArbitrumEnv"));
    else if (network == Network.Optimism) return Env(_deployCode("TestSetup.t.sol:OptimismEnv"));
    else if (network == Network.Polygon) return Env(_deployCode("TestSetup.t.sol:PolygonEnv"));
    else if (network == Network.Mainnet) return Env(_deployCode("TestSetup.t.sol:MainnetEnv"));
    else if (network == Network.Gnosis) return Env(_deployCode("TestSetup.t.sol:GnosisEnv"));
    else if (network == Network.Base) return Env(_deployCode("TestSetup.t.sol:BaseEnv"));
    else if (network == Network.Bsc) return Env(_deployCode("TestSetup.t.sol:BscEnv"));
    else if (network == Network.Linea) return Env(_deployCode("TestSetup.t.sol:LineaEnv"));
    else if (network == Network.Scroll) return Env(_deployCode("TestSetup.t.sol:ScrollEnv"));
    else if (network == Network.Avalanche) return Env(_deployCode("TestSetup.t.sol:AvalancheEnv"));
    else revert(string.concat("Unsupported network: ", network.toString()));
}

function forkBlock(Network network) pure returns (uint256) {
    if (network == Network.Arbitrum) return 98_674_994;
    else if (network == Network.Optimism) return 107_312_284;
    else if (network == Network.Polygon) return 45_578_550;
    else if (network == Network.Mainnet) return 18_012_703;
    else if (network == Network.Gnosis) return 30_772_017;
    else if (network == Network.Base) return 6_372_881;
    else if (network == Network.Bsc) return 39_407_478;
    else if (network == Network.Linea) return 7_910_918;
    else if (network == Network.Scroll) return 8_225_281;
    else if (network == Network.Avalanche) return 49_053_214;
    else revert(string.concat("Unsupported network: ", network.toString()));
}

struct TestInstrument {
    Symbol symbol;
    ERC20Data baseData;
    IERC20 base;
    uint8 baseDecimals;
    uint256 baseUnit;
    ERC20Data quoteData;
    IERC20 quote;
    uint8 quoteDecimals;
    uint256 quoteUnit;
}

struct ERC20Data {
    bytes32 symbol;
    IERC20 token;
    IAggregatorV2V3 chainlinkUsdOracle;
    bool hasPermit;
}

struct ERC20Bounds {
    uint256 min;
    uint256 max;
    uint256 dust;
}

function slippage(uint256 value, uint256 _slippage) pure returns (uint256) {
    return Math.mulDiv(value, _slippage, 1e4, Math.Rounding.Up);
}

function slippage(uint256 value) pure returns (uint256) {
    return slippage(value, DEFAULT_SLIPPAGE_TOLERANCE);
}

function discountSlippage(uint256 value) pure returns (uint256) {
    return value - slippage(value);
}

function addSlippage(uint256 value) pure returns (uint256) {
    return value + slippage(value);
}

/// @dev returns the init code (creation code + ABI-encoded args) used in CREATE2
/// @param creationCode the creation code of a contract C, as returned by type(C).creationCode
/// @param args the ABI-encoded arguments to the constructor of C
function initCode(bytes memory creationCode, bytes memory args) pure returns (bytes memory) {
    return abi.encodePacked(creationCode, args);
}

struct Deployment {
    Maestro maestro;
    Vault vault;
    Contango contango;
    ContangoLens contangoLens;
    IOrderManager orderManager;
    TSQuoter tsQuoter;
    StrategyBuilder strategyBuilder;
}

contract Deployer is Addresses {

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    function deployAaveMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveMoneyMarket(contango, MM_AAVE, env.aaveAddressProvider(), env.aaveRewardsController(), true);
    }

    function deployAaveLidoMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveMoneyMarket(contango, MM_AAVE_LIDO, env.aaveLidoAddressProvider(), env.aaveLidoRewardsController(), true);
    }

    function deployZeroLendMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveMoneyMarket(contango, MM_ZEROLEND, env.zeroLendAddressProvider(), env.zeroLendRewardsController(), true);
    }

    function deployAaveMoneyMarket(
        IContango contango,
        MoneyMarketId mmId,
        IPoolAddressesProvider _poolAddressesProvider,
        IAaveRewardsController _rewardsController,
        bool _flashBorrowEnabled
    ) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AaveMoneyMarket({
            _moneyMarketId: mmId,
            _contango: contango,
            _poolAddressesProvider: _poolAddressesProvider,
            _rewardsController: _rewardsController,
            _flashBorrowEnabled: _flashBorrowEnabled
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployAaveV2MoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveV2MoneyMarket(contango, MM_AAVE_V2, env.aaveV2AddressProvider(), IAaveRewardsController(address(0)));
    }

    function deployRadiantMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveV2MoneyMarket(contango, MM_RADIANT, env.radiantAddressProvider(), IAaveRewardsController(address(0)));
    }

    function deployAaveV2MoneyMarket(
        IContango contango,
        MoneyMarketId mmId,
        IPoolAddressesProviderV2 _poolAddressesProvider,
        IAaveRewardsController _rewardsController
    ) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AaveV2MoneyMarket({
            _moneyMarketId: mmId,
            _contango: contango,
            _poolAddressesProvider: IPoolAddressesProvider(address(_poolAddressesProvider)),
            _rewardsController: _rewardsController,
            _flashBorrowEnabled: true
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deploySparkSkyMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = deployAaveMoneyMarket(contango, MM_SPARK_SKY, env.sparkAddressProvider(), env.sparkRewardsController(), false);
    }

    function _update(ExactlyReverseLookup reverseLookup) private {
        IExactlyMarket[] memory allMarkets = reverseLookup.auditor().allMarkets();
        for (uint256 i = 0; i < allMarkets.length; i++) {
            IExactlyMarket _market = allMarkets[i];
            reverseLookup.setMarket(_market);
        }
    }

    function deployExactlyMoneyMarket(Env env, IContango contango) public returns (ExactlyMoneyMarket moneyMarket) {
        ExactlyReverseLookup reverseLookup = new ExactlyReverseLookup(env.auditor());
        _update(reverseLookup);
        moneyMarket = new ExactlyMoneyMarket({
            _moneyMarketId: MM_EXACTLY,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _rewardsController: IExactlyRewardsController(0xBd1ba78A3976cAB420A9203E6ef14D18C2B2E031)
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = ExactlyMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployCometMoneyMarket(Env env, IContango contango) public returns (CometMoneyMarket moneyMarket) {
        CometReverseLookup reverseLookup = new CometReverseLookup(TIMELOCK, env.operator());
        moneyMarket = new CometMoneyMarket({
            _moneyMarketId: MM_COMET,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _rewards: env.cometRewards()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = CometMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function _update(CompoundReverseLookup reverseLookup) private {
        ICToken[] memory allMarkets = reverseLookup.comptroller().getAllMarkets();
        for (uint256 i = 0; i < allMarkets.length; i++) {
            ICToken _cToken = allMarkets[i];
            reverseLookup.setCToken(_cToken);
        }
    }

    function deployCompoundMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(env.compoundComptroller(), env.nativeToken());
        _update(reverseLookup);
        moneyMarket = new CompoundMoneyMarket({
            _moneyMarketId: MM_COMPOUND,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deploySonneMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(env.compoundComptroller(), env.nativeToken());
        _update(reverseLookup);
        moneyMarket = new CompoundMoneyMarket({
            _moneyMarketId: MM_SONNE,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: IWETH9(address(0))
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployMoonwellMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(env.moonwellComptroller(), env.nativeToken());
        _update(reverseLookup);
        moneyMarket = new MoonwellMoneyMarket({
            _moneyMarketId: MM_MOONWELL,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployLodestarMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(env.compoundComptroller(), env.nativeToken());
        _update(reverseLookup);
        moneyMarket = new CompoundMoneyMarket({
            _moneyMarketId: MM_LODESTAR,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployMorphoBlueMoneyMarket(Env env, IContango contango) public returns (MorphoBlueMoneyMarket moneyMarket) {
        moneyMarket = new MorphoBlueMoneyMarket({
            _moneyMarketId: MM_MORPHO_BLUE,
            _contango: contango,
            _morpho: env.morpho(),
            _reverseLookup: new MorphoBlueReverseLookup(env.morpho()),
            _ena: new ERC20Mock()
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = MorphoBlueMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deploySiloMoneyMarket(Env env, IContango contango) public returns (SiloMoneyMarket moneyMarket) {
        IERC20 stable = env.network().isArbitrum() ? env.token(USDC) : IERC20(address(0));

        moneyMarket = new SiloMoneyMarket(MM_SILO, contango, env.siloLens(), env.wstEthSilo(), env.nativeToken(), stable);

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = SiloMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployDolomiteMoneyMarket(Env env, IContango contango) public returns (DolomiteMoneyMarket moneyMarket) {
        moneyMarket = new DolomiteMoneyMarket(contango, env.dolomite());

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = DolomiteMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployEulerMoneyMarket(Env env, IContango contango) public returns (EulerMoneyMarket moneyMarket) {
        EulerReverseLookup reverseLookup = new EulerReverseLookup(TIMELOCK);

        EulerRewardsOperator rewardsOperator = new EulerRewardsOperator(
            TIMELOCK, contango.positionNFT(), contango.positionFactory(), env.eulerVaultConnector(), env.eulerRewards(), reverseLookup
        );

        moneyMarket = new EulerMoneyMarket(contango, env.eulerVaultConnector(), env.eulerRewards(), reverseLookup, rewardsOperator);

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = EulerMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployFluidMoneyMarket(Env env, IContango contango) public returns (FluidMoneyMarket moneyMarket) {
        moneyMarket = new FluidMoneyMarket(contango, env.nativeToken(), env.fluidVaultResolver());

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), Timelock.wrap(address(this)));
        moneyMarket = FluidMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployVault(Env env) public returns (Vault vault) {
        vault = new Vault(env.nativeToken());
        vault.initialize(TIMELOCK);
        VM.label(address(vault), "Vault");
        VM.prank(TIMELOCK_ADDRESS);
        vault.grantRole(OPERATOR_ROLE, TIMELOCK_ADDRESS);
    }

    function deployStrategyBuilder(Env env) public returns (StrategyBuilder strategyBuilder) {
        strategyBuilder = new StrategyBuilder(env.maestro(), env.erc721Permit2(), env.contangoLens());
        strategyBuilder.initialize(TIMELOCK);
        VM.label(address(strategyBuilder), "StrategyBuilder");
    }

    function deployContango(Env env) public returns (Deployment memory deployment) {
        PositionNFT positionNFT = new PositionNFT(TIMELOCK);
        UnderlyingPositionFactory positionFactory = new UnderlyingPositionFactory(TIMELOCK);

        deployment.vault = deployVault(env);
        deployment.contango = new Contango(positionNFT, deployment.vault, positionFactory, new SpotExecutor());
        Contango(payable(address(deployment.contango))).initialize(TIMELOCK);

        deployment.contangoLens = new ContangoLens(deployment.contango);
        ContangoLens(address(deployment.contangoLens)).initialize(TIMELOCK);

        deployment.tsQuoter = new TSQuoter(Contango(payable(address(deployment.contango))), deployment.contangoLens);

        VM.startPrank(TIMELOCK_ADDRESS);
        deployment.contango.grantRole(OPERATOR_ROLE, TIMELOCK_ADDRESS);
        deployment.contangoLens.grantRole(OPERATOR_ROLE, TIMELOCK_ADDRESS);
        positionFactory.grantRole(CONTANGO_ROLE, address(deployment.contango));

        if (env.marketAvailable(MM_AAVE)) {
            positionFactory.registerMoneyMarket(deployAaveMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new AaveMoneyMarketView(
                    MM_AAVE,
                    "AaveV3",
                    deployment.contango,
                    env.aaveAddressProvider(),
                    env.aaveRewardsController(),
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    AaveMoneyMarketView.Version.V32
                )
            );
        }
        if (env.marketAvailable(MM_AAVE_LIDO) && env.blockNumber() >= 20_420_912) {
            positionFactory.registerMoneyMarket(deployAaveLidoMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new AaveMoneyMarketView(
                    MM_AAVE_LIDO,
                    "AaveLido",
                    deployment.contango,
                    env.aaveLidoAddressProvider(),
                    env.aaveLidoRewardsController(),
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    AaveMoneyMarketView.Version.V32
                )
            );
        }

        if (env.marketAvailable(MM_ZEROLEND)) {
            positionFactory.registerMoneyMarket(deployZeroLendMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new AaveMoneyMarketView(
                    MM_ZEROLEND,
                    "ZeroLend",
                    deployment.contango,
                    env.zeroLendAddressProvider(),
                    env.zeroLendRewardsController(),
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    AaveMoneyMarketView.Version.V3
                )
            );
        }
        if (env.marketAvailable(MM_EXACTLY)) {
            ExactlyMoneyMarket moneyMarket = deployExactlyMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new ExactlyMoneyMarketView(
                    MM_EXACTLY,
                    "Exactly",
                    deployment.contango,
                    moneyMarket.reverseLookup(),
                    env.auditor(),
                    env.previewer(),
                    env.nativeToken(),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_COMPOUND)) {
            CompoundMoneyMarket moneyMarket = deployCompoundMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(deployCompoundMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new CompoundMoneyMarketView(
                    MM_COMPOUND, "CompoundV2", deployment.contango, moneyMarket.reverseLookup(), env.compOracle(), env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_SONNE)) {
            CompoundMoneyMarket moneyMarket = deploySonneMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new SonneMoneyMarketView(deployment.contango, moneyMarket.reverseLookup(), env.sonneOracle(), env.nativeUsdOracle())
            );
        }
        if (env.marketAvailable(MM_SPARK_SKY)) {
            positionFactory.registerMoneyMarket(deploySparkSkyMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new AaveMoneyMarketView(
                    MM_SPARK_SKY,
                    "Spark",
                    deployment.contango,
                    env.sparkAddressProvider(),
                    env.sparkRewardsController(),
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    AaveMoneyMarketView.Version.V3
                )
            );
        }
        if (env.marketAvailable(MM_MORPHO_BLUE)) {
            MorphoBlueMoneyMarket mm = deployMorphoBlueMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(mm);
            deployment.contangoLens.setMoneyMarketView(
                new MorphoBlueMoneyMarketView(
                    MM_MORPHO_BLUE,
                    "Morpho Blue",
                    deployment.contango,
                    env.morpho(),
                    mm.reverseLookup(),
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    new ERC20Mock()
                )
            );
        }
        if (env.marketAvailable(MM_AAVE_V2)) {
            positionFactory.registerMoneyMarket(deployAaveV2MoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new AaveV2MoneyMarketView(
                    MM_AAVE_V2,
                    "AaveV2",
                    deployment.contango,
                    IPoolAddressesProvider(address(env.aaveV2AddressProvider())),
                    env.aaveV2PoolDataProvider(),
                    1e18,
                    env.nativeToken(),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_RADIANT)) {
            positionFactory.registerMoneyMarket(deployRadiantMoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new AaveV2MoneyMarketView(
                    MM_RADIANT,
                    "Radiant",
                    deployment.contango,
                    IPoolAddressesProvider(address(env.radiantAddressProvider())),
                    env.radiantPoolDataProvider(),
                    1e8,
                    env.nativeToken(),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_LODESTAR) && env.blockNumber() >= 152_284_580) {
            CompoundMoneyMarket moneyMarket = deployLodestarMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new LodestarMoneyMarketView(deployment.contango, moneyMarket.reverseLookup(), env.lodestarOracle(), env.nativeUsdOracle())
            );
        }
        if (env.marketAvailable(MM_MOONWELL)) {
            CompoundMoneyMarket moneyMarket = deployMoonwellMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new MoonwellMoneyMarketView(
                    deployment.contango,
                    moneyMarket.reverseLookup(),
                    env.bridgedMoonwellOracle(),
                    env.bridgedMoonwellToken(),
                    env.nativeMoonwellOracle(),
                    env.nativeMoonwellToken(),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_COMET)) {
            CometMoneyMarket moneyMarket = deployCometMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new CometMoneyMarketView(
                    deployment.contango, env.nativeToken(), env.nativeUsdOracle(), moneyMarket.reverseLookup(), env.cometRewards()
                )
            );
        }
        if (env.marketAvailable(MM_SILO)) {
            positionFactory.registerMoneyMarket(deploySiloMoneyMarket(env, deployment.contango));

            IERC20 stable = env.network().isArbitrum() ? env.token(USDC) : IERC20(address(0));

            deployment.contangoLens.setMoneyMarketView(
                new SiloMoneyMarketView(
                    MM_SILO, deployment.contango, env.nativeToken(), env.nativeUsdOracle(), env.siloLens(), env.wstEthSilo(), stable
                )
            );
        }
        if (env.marketAvailable(MM_DOLOMITE)) {
            positionFactory.registerMoneyMarket(deployDolomiteMoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new DolomiteMoneyMarketView(deployment.contango, env.nativeToken(), env.nativeUsdOracle(), env.dolomite())
            );
        }
        if (env.marketAvailable(MM_EULER) && block.number >= 20_678_328) {
            EulerMoneyMarket mm = deployEulerMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(mm);

            deployment.contangoLens.setMoneyMarketView(
                new EulerMoneyMarketView(
                    deployment.contango, env.nativeToken(), env.nativeUsdOracle(), mm.reverseLookup(), mm.rewardOperator(), env.eulerLens()
                )
            );
        }

        if (env.marketAvailable(MM_FLUID) && block.number >= 20_678_328) {
            FluidMoneyMarket mm = deployFluidMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(mm);

            deployment.contangoLens.setMoneyMarketView(
                new FluidMoneyMarketView(deployment.contango, env.nativeToken(), env.nativeUsdOracle(), env.fluidVaultResolver())
            );
        }

        positionNFT.grantRole(MINTER_ROLE, address(deployment.contango));

        // Flash loan providers
        {
            TestFLP flp = new TestFLP();
            deployment.tsQuoter.addFlashLoanProvider(flp);
            env.setFlashLoanProvider(flp);
            VM.allowCheatcodes(address(flp));
        }

        VM.stopPrank();

        deployment.orderManager = new OrderManager(deployment.contango, TREASURY);
        OrderManager(payable(address(deployment.orderManager))).initialize({
            timelock: TIMELOCK,
            _gasMultiplier: 2e4,
            _gasTip: 0,
            _oracle: deployment.contangoLens
        });

        deployment.maestro = new Maestro(
            TIMELOCK,
            deployment.contango,
            deployment.orderManager,
            deployment.vault,
            env.permit2(),
            new SimpleSpotExecutor(),
            TREASURY,
            new Router()
        );
        VM.label(address(deployment.maestro), "Maestro");

        VM.startPrank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(deployment.maestro), true);
        positionNFT.setContangoContract(address(deployment.orderManager), true);
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.maestro));
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.contango));
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.orderManager));
        VM.stopPrank();
    }

}

function toString(Currency currency) pure returns (string memory) {
    if (currency == Currency.None) return "None";
    else if (currency == Currency.Base) return "Base";
    else if (currency == Currency.Quote) return "Quote";
    else revert("Unsupported currency");
}

function toString(MoneyMarketId mm) pure returns (string memory) {
    uint256 mmId = MoneyMarketId.unwrap(mm);
    if (mmId == MoneyMarketId.unwrap(MM_AAVE)) return "AaveV3";
    else if (mmId == MoneyMarketId.unwrap(MM_COMPOUND)) return "Compound";
    else if (mmId == MoneyMarketId.unwrap(MM_EXACTLY)) return "Exactly";
    else if (mmId == MoneyMarketId.unwrap(MM_SONNE)) return "Sonne";
    else if (mmId == MoneyMarketId.unwrap(MM_SPARK_SKY)) return "SparkSky";
    else if (mmId == MoneyMarketId.unwrap(MM_MORPHO_BLUE)) return "MorphoBlue";
    else if (mmId == MoneyMarketId.unwrap(MM_AAVE_V2)) return "AaveV2";
    else if (mmId == MoneyMarketId.unwrap(MM_RADIANT)) return "Radiant";
    else revert(string.concat("Unsupported money market: ", VM.toString(mmId)));
}

abstract contract Env is StdAssertions, StdCheats, Addresses {

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    // Aave
    IPoolAddressesProvider public aaveAddressProvider;
    IAaveRewardsController public aaveRewardsController;
    // ZeroLend
    IPoolAddressesProvider public zeroLendAddressProvider;
    IAaveRewardsController public zeroLendRewardsController;
    // AaveLido
    IPoolAddressesProvider public aaveLidoAddressProvider;
    IAaveRewardsController public aaveLidoRewardsController;
    // Aave V2
    IPoolAddressesProviderV2 public aaveV2AddressProvider;
    IPoolDataProviderV2 public aaveV2PoolDataProvider;
    // Radiant
    IPoolAddressesProviderV2 public radiantAddressProvider;
    IPoolDataProviderV2 public radiantPoolDataProvider;
    // Compound
    IComptroller public compoundComptroller;
    address public compOracle;
    // Exactly
    IAuditor public auditor;
    IExactlyPreviewer public previewer;
    // Spark
    IPoolAddressesProvider public sparkAddressProvider;
    IAaveRewardsController public sparkRewardsController;
    // Morpho
    IMorpho public morpho;
    // Uniswap
    address public uniswap;
    SwapRouter02 public uniswapRouter;
    // Sonne
    address public sonneOracle;
    // Lodestar
    address public lodestarOracle;
    // Comet
    IComet public comet;
    ICometRewards public cometRewards;
    // Moonwell
    IComptroller public moonwellComptroller;
    address public bridgedMoonwellOracle;
    IERC20 public bridgedMoonwellToken;
    address public nativeMoonwellOracle;
    IERC20 public nativeMoonwellToken;
    // Silo
    ISiloLens public siloLens;
    ISilo public wstEthSilo;
    // Dolomite
    IDolomiteMargin public dolomite;
    // Euler
    IEthereumVaultConnector public eulerVaultConnector;
    IRewardStreams public eulerRewards;
    IEulerVaultLens public eulerLens;
    // Fluid
    IFluidVaultResolver public fluidVaultResolver;
    // Test
    SpotStub public spotStub;
    PositionActions public positionActions;
    PositionActions public positionActions2;
    // Contango
    Contango public contango;
    Vault public vault;
    Maestro public maestro;
    IOrderManager public orderManager;
    IUnderlyingPositionFactory public positionFactory;
    Encoder public encoder;
    TSQuoter public tsQuoter;
    ContangoLens public contangoLens;
    PositionNFT public positionNFT;
    StrategyBuilder public strategyBuilder;
    // Chain
    IWETH9 public nativeToken;
    IAggregatorV2V3 public nativeUsdOracle;
    // MultiChain
    IPermit2 public permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // Flash loan providers
    TestFLP public flashLoanProvider;

    ERC721Permit2 public erc721Permit2;

    Network public network;
    Deployer public deployer;
    MoneyMarketId[] internal _moneyMarkets;
    MoneyMarketId[] internal _fuzzMoneyMarkets;
    IERC7399[] internal _flashLoanProviders;
    mapping(bytes32 => ERC20Data) internal _erc20s;
    mapping(bytes32 => ERC20Bounds) internal _bounds;
    mapping(Symbol => TestInstrument) public _instruments;

    uint256 public blockNumber;

    Operator public constant operator = Operator.wrap(TIMELOCK_ADDRESS);

    constructor(Network _network) {
        VM.makePersistent(address(this));
        network = _network;

        deployer = Deployer(deployCode("TestSetup.t.sol:Deployer"));
        VM.makePersistent(address(deployer));

        positionActions = PositionActions(deployCode("PositionActions.sol:PositionActions", abi.encode(this, TRADER, TRADER_PK)));
        VM.makePersistent(address(positionActions));

        positionActions2 = PositionActions(deployCode("PositionActions.sol:PositionActions", abi.encode(this, TRADER2, TRADER2_PK)));
        VM.makePersistent(address(positionActions2));

        _bounds[LINK] = ERC20Bounds({ min: 15e18, max: type(uint96).max, dust: 0.000001e18 });
        _bounds[DAI] = ERC20Bounds({ min: 100e18, max: type(uint96).max, dust: 0.0001e18 });
        _bounds[SDAI] = ERC20Bounds({ min: 100e18, max: type(uint96).max, dust: 0.0001e18 });
        _bounds[USDC] = ERC20Bounds({ min: 100e6, max: type(uint96).max / 1e12, dust: 0.0001e6 });
        if (network.isBsc()) _bounds[USDT] = ERC20Bounds({ min: 100e18, max: type(uint96).max, dust: 0.0001e18 });
        else _bounds[USDT] = ERC20Bounds({ min: 100e6, max: type(uint96).max / 1e12, dust: 0.0001e6 });
        _bounds[WETH] = ERC20Bounds({ min: 0.1e18, max: type(uint96).max, dust: 0.00001e18 });
    }

    function init() public virtual;

    function init(uint256 _blockNumber) public virtual {
        nativeToken = IWETH9(address(token(WETH)));
        blockNumber = _blockNumber;
    }

    function cleanTreasury() public virtual {
        VM.deal(TREASURY, 0);
        deal(address(token(WETH)), TREASURY, 0);
        // deal(address(token(LINK)), TREASURY, 0);
        deal(address(token(DAI)), TREASURY, 0);
        // deal(address(token(SDAI)), TREASURY, 0);
        deal(address(token(USDC)), TREASURY, 0);
    }

    function canPrank() public virtual returns (bool) {
        return true;
    }

    function moneyMarkets() external view returns (MoneyMarketId[] memory) {
        return _moneyMarkets;
    }

    function fuzzMoneyMarkets() external view returns (MoneyMarketId[] memory) {
        return _fuzzMoneyMarkets;
    }

    function marketAvailable(MoneyMarketId mm) public view returns (bool) {
        for (uint256 i = 0; i < _moneyMarkets.length; i++) {
            if (MoneyMarketId.unwrap(_moneyMarkets[i]) == MoneyMarketId.unwrap(mm)) return true;
        }
        return false;
    }

    function flashLoanProviders() external view returns (IERC7399[] memory) {
        return _flashLoanProviders;
    }

    function setFlashLoanProvider(TestFLP _flashLoanProvider) public {
        _flashLoanProviders.push(_flashLoanProvider);
        flashLoanProvider = _flashLoanProvider;
    }

    function erc20(bytes32 symbol) public view returns (ERC20Data memory erc20Data) {
        erc20Data = _erc20s[symbol];
        require(address(erc20Data.token) != address(0), string.concat("Token not found: ", bytes32ToString(symbol)));
    }

    function token(bytes32 symbol) public view returns (IERC20) {
        return erc20(symbol).token;
    }

    function bounds(bytes32 symbol) public view returns (ERC20Bounds memory erc20Bounds) {
        erc20Bounds = _bounds[symbol];
        require(erc20Bounds.min > 0, "Bounds not found");
    }

    ERC20Data[] tmp;
    bytes32[] public allTokens = [LINK, DAI, USDC, WETH];

    function erc20s(MoneyMarketId mm) public returns (ERC20Data[] memory) {
        delete tmp;

        uint256 mmId = MoneyMarketId.unwrap(mm);
        if (mmId == MoneyMarketId.unwrap(MM_AAVE)) {
            tmp.push(erc20(LINK));
            tmp.push(erc20(DAI));
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else if (mmId == MoneyMarketId.unwrap(MM_RADIANT)) {
            tmp.push(erc20(DAI));
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else if (mmId == MoneyMarketId.unwrap(MM_COMPOUND)) {
            tmp.push(erc20(DAI));
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else if (mmId == MoneyMarketId.unwrap(MM_SONNE)) {
            tmp.push(erc20(DAI));
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else if (mmId == MoneyMarketId.unwrap(MM_EXACTLY)) {
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else {
            revert(string.concat("Unsupported money market: ", VM.toString(mmId)));
        }

        return tmp;
    }

    function createInstrumentAndPositionId(IERC20 base, IERC20 quote, MoneyMarketId mm)
        public
        returns (Symbol symbol, Instrument memory instrument, PositionId positionId)
    {
        (symbol, instrument) = createInstrument(base, quote);
        positionId = encoder.encodePositionId(base, quote, mm, PERP, 0);
    }

    function createInstrument(IERC20 base, IERC20 quote) public returns (Symbol symbol, Instrument memory instrument) {
        symbol = Symbol.wrap(bytes16(abi.encodePacked(base.symbol(), quote.symbol())));
        instrument = contango.instrument(symbol);
        if (instrument.base == IERC20(address(0))) {
            VM.startPrank(TIMELOCK_ADDRESS);
            contango.createInstrument({ symbol: symbol, base: base, quote: quote });
            vault.setTokenSupport(base, true);
            vault.setTokenSupport(quote, true);
            VM.stopPrank();
            instrument = contango.instrument(symbol);
        }
    }

    function createInstrument(ERC20Data memory baseData, ERC20Data memory quoteData) public returns (TestInstrument memory instrument) {
        createInstrument(baseData.token, quoteData.token);
        return loadInstrument(baseData, quoteData);
    }

    function loadInstrument(ERC20Data memory baseData, ERC20Data memory quoteData) public returns (TestInstrument memory instrument) {
        Symbol symbol = Symbol.wrap(bytes16(abi.encodePacked(baseData.token.symbol(), quoteData.token.symbol())));
        instrument = TestInstrument({
            symbol: symbol,
            baseData: baseData,
            base: baseData.token,
            baseDecimals: baseData.token.decimals(),
            baseUnit: 10 ** baseData.token.decimals(),
            quoteData: quoteData,
            quote: quoteData.token,
            quoteDecimals: quoteData.token.decimals(),
            quoteUnit: 10 ** quoteData.token.decimals()
        });
        _instruments[symbol] = instrument;
    }

    function instruments(Symbol symbol) public view returns (TestInstrument memory) {
        return _instruments[symbol];
    }

    function assertNoBalances(IERC20 _token, address addr, uint256 dust, string memory label) public view {
        uint256 balance = address(_token) == address(0) ? addr.balance : _token.balanceOf(addr);
        assertApproxEqAbsDecimal(balance, 0, dust, _token.decimals(), label);
    }

    function checkInvariants(TestInstrument memory instrument, PositionId positionId) public view {
        assertNoBalances(instrument, positionId);
    }

    function checkInvariants(TestInstrument memory instrument, PositionId positionId, uint256 contangoBaseTolerance) public view {
        assertNoBalances(instrument, positionId, contangoBaseTolerance);
    }

    function assertNoBalances(TestInstrument memory instrument, PositionId positionId) public view {
        assertNoBalances(instrument, positionId, bounds(instrument.baseData.symbol).dust);
    }

    function assertNoBalances(TestInstrument memory instrument, PositionId positionId, uint256 contangoBaseTolerance) public view {
        assertNoBalances(instrument.base, address(contango), contangoBaseTolerance, "contango balance: base");
        assertNoBalances(instrument.quote, address(contango), bounds(instrument.quoteData.symbol).dust, "contango balance: quote");
        assertNoBalances(
            instrument.base, address(positionFactory.moneyMarket(positionId)), bounds(instrument.baseData.symbol).dust, "MM balance: base"
        );
        assertNoBalances(
            instrument.quote,
            address(positionFactory.moneyMarket(positionId)),
            bounds(instrument.quoteData.symbol).dust,
            "MM balance: quote"
        );
    }

    function deposit(IERC20 _token, address to, uint256 amount) public {
        deal(address(_token), to, amount);

        VM.prank(to);
        _token.transfer(address(vault), amount);

        VM.prank(to);
        maestro.deposit(_token, amount);
    }

    function dealAndApprove(IERC20 _token, address to, uint256 amount, address approveTo) public virtual {
        deal(address(_token), to, amount);
        VM.prank(to);
        _token.approve(approveTo, amount);
    }

    function dealAndPermit(IERC20 _token, address to, uint256 toPk, uint256 amount, address approveTo)
        public
        virtual
        returns (EIP2098Permit memory signedPermit)
    {
        deal(address(_token), to, amount);
        return signPermit(_token, to, toPk, approveTo, amount);
    }

    function dealAndPermit2(IERC20 _token, address to, uint256 toPk, uint256 amount, address approveTo)
        public
        virtual
        returns (EIP2098Permit memory signedPermit)
    {
        dealAndApprove(_token, to, amount, address(permit2));

        signedPermit.deadline = type(uint32).max;
        signedPermit.amount = amount;

        (uint8 v, bytes32 r, bytes32 s) = VM.sign(toPk, keccak256(_encodePermit2(_token, amount, signedPermit.deadline, to, approveTo)));

        signedPermit.r = r;
        signedPermit.vs = _encode(s, v);
    }

    function _encodePermit2(IERC20 _token, uint256 amount, uint256 deadline, address to, address approveTo)
        private
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            "\x19\x01",
            permit2.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        // solhint-disable-next-line max-line-length
                        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
                    ),
                    keccak256(abi.encode(keccak256("TokenPermissions(address token,uint256 amount)"), _token, amount)),
                    approveTo,
                    uint256(keccak256(abi.encode(to, _token, amount, deadline))),
                    deadline
                )
            )
        );
    }

    function positionIdPermit2(PositionId positionId, address owner, uint256 ownerPk, address spender)
        public
        virtual
        returns (PositionPermit memory signedPermit)
    {
        signedPermit.deadline = type(uint32).max;
        signedPermit.positionId = positionId;

        (uint8 v, bytes32 r, bytes32 s) =
            VM.sign(ownerPk, keccak256(_encodeERC721Permit2(positionId, signedPermit.deadline, owner, spender)));

        signedPermit.r = r;
        signedPermit.vs = _encode(s, v);
    }

    function _encodeERC721Permit2(PositionId positionId, uint256 deadline, address owner, address spender)
        private
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            "\x19\x01",
            erc721Permit2.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    PermitHash._PERMIT_TRANSFER_FROM_TYPEHASH,
                    keccak256(abi.encode(PermitHash._TOKEN_PERMISSIONS_TYPEHASH, positionNFT, positionId)),
                    spender,
                    uint256(keccak256(abi.encode(owner, positionNFT, positionId, deadline))),
                    deadline
                )
            )
        );
    }

}

contract ArbitrumEnv is Env {

    constructor() Env(Network.Arbitrum) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_RADIANT);
        _moneyMarkets.push(MM_LODESTAR);
        _moneyMarkets.push(MM_SILO);
        _moneyMarkets.push(MM_DOLOMITE);

        _fuzzMoneyMarkets.push(MM_AAVE);
        _fuzzMoneyMarkets.push(MM_RADIANT);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4),
            chainlinkUsdOracle: IAggregatorV2V3(0x86E53CF1B870786351Da77A57575e79CB55812CB),
            hasPermit: true
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            chainlinkUsdOracle: IAggregatorV2V3(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8),
            chainlinkUsdOracle: IAggregatorV2V3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
            hasPermit: true
        });
        _erc20s[USDCn] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
            chainlinkUsdOracle: IAggregatorV2V3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
            chainlinkUsdOracle: IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            hasPermit: true
        });
        _erc20s[USDT] = ERC20Data({
            symbol: USDT,
            token: IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
            chainlinkUsdOracle: IAggregatorV2V3(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7),
            hasPermit: true
        });
        _erc20s[ARB] = ERC20Data({
            symbol: ARB,
            token: IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548),
            chainlinkUsdOracle: IAggregatorV2V3(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6),
            hasPermit: true
        });
        _erc20s[LUSD] = ERC20Data({
            symbol: LUSD,
            token: IERC20(0x93b346b6BC2548dA6A1E7d98E9a421B42541425b),
            chainlinkUsdOracle: IAggregatorV2V3(0x0411D28c94d85A36bC72Cb0f875dfA8371D8fFfF),
            hasPermit: true
        });
        _erc20s[WBTC] = ERC20Data({
            symbol: WBTC,
            token: IERC20(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f),
            chainlinkUsdOracle: IAggregatorV2V3(0xd0C7101eACbB49F3deCcCc166d238410D6D46d57),
            hasPermit: true
        });
        _erc20s[PTweETH27JUN2024] = ERC20Data({
            symbol: PTweETH27JUN2024,
            token: IERC20(0x1c27Ad8a19Ba026ADaBD615F6Bc77158130cfBE4),
            chainlinkUsdOracle: IAggregatorV2V3(0x86E53CF1B870786351Da77A57575e79CB55812CB), // Hack (LINK / USD)
            hasPermit: false
        });
        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4),
            chainlinkUsdOracle: IAggregatorV2V3(0x86E53CF1B870786351Da77A57575e79CB55812CB),
            hasPermit: true
        });
        _erc20s[PENDLE] = ERC20Data({
            symbol: PENDLE,
            token: IERC20(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8),
            chainlinkUsdOracle: IAggregatorV2V3(0x66853E19d73c0F9301fe099c324A1E9726953433),
            hasPermit: true
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        aaveRewardsController = IAaveRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
        radiantAddressProvider = IPoolAddressesProviderV2(0x091d52CacE1edc5527C99cDCFA6937C1635330E4);
        radiantPoolDataProvider = IPoolDataProviderV2(0x596B0cc4c5094507C50b579a662FE7e7b094A2cC);
        compoundComptroller = IComptroller(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
        lodestarOracle = 0x49bB23DfAe944059C2403BCc255c5a9c0F851a8D;
        nativeUsdOracle = IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
        siloLens = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
        wstEthSilo = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
    }

    function init() public override {
        init(forkBlock(Network.Arbitrum));
    }

    function init(uint256 blockNumber) public virtual override {
        super.init(blockNumber);
        fork("arbitrum", blockNumber);
        cleanTreasury();

        dolomite = IDolomiteMargin(_loadAddress("DolomiteMargin"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract OptimismEnv is Env {

    constructor() Env(Network.Optimism) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_EXACTLY);
        _moneyMarkets.push(MM_SONNE);

        _fuzzMoneyMarkets.push(MM_AAVE);
        _fuzzMoneyMarkets.push(MM_EXACTLY);
        _fuzzMoneyMarkets.push(MM_SONNE);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6),
            chainlinkUsdOracle: IAggregatorV2V3(0xCc232dcFAAE6354cE191Bd574108c1aD03f86450),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            chainlinkUsdOracle: IAggregatorV2V3(0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607),
            chainlinkUsdOracle: IAggregatorV2V3(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x4200000000000000000000000000000000000006),
            chainlinkUsdOracle: IAggregatorV2V3(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
            hasPermit: false
        });
        _erc20s[WSTETH] = ERC20Data({
            symbol: WSTETH,
            token: IERC20(0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb),
            chainlinkUsdOracle: IAggregatorV2V3(0x698B585CbC4407e2D54aa898B2600B53C68958f7),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        aaveRewardsController = IAaveRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
        auditor = IAuditor(0xaEb62e6F27BC103702E7BC879AE98bceA56f027E);
        previewer = IExactlyPreviewer(0xb8b1f590272b541b263A49b28bF52f8774b0E6c9);
        compoundComptroller = IComptroller(0x60CF091cD3f50420d50fD7f707414d0DF4751C58);
        sonneOracle = 0x4E60495550071693bc8bDfFC40033d278157EAC7;
        nativeUsdOracle = IAggregatorV2V3(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
    }

    function init() public override {
        init(forkBlock(Network.Optimism));
    }

    function init(uint256 blockNumber) public virtual override {
        super.init(blockNumber);
        fork("optimism", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract PolygonEnv is Env {

    constructor() Env(Network.Polygon) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_AAVE_V2);
        _moneyMarkets.push(MM_COMET);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0xb0897686c545045aFc77CF20eC7A532E3120E0F1),
            chainlinkUsdOracle: IAggregatorV2V3(0xd9FFdb71EbE7496cC440152d43986Aae0AB76665),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063),
            chainlinkUsdOracle: IAggregatorV2V3(0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174),
            chainlinkUsdOracle: IAggregatorV2V3(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
            chainlinkUsdOracle: IAggregatorV2V3(0xF9680D99D6C9589e2a93a78A04A279e509205945),
            hasPermit: false
        });
        _erc20s[WMATIC] = ERC20Data({
            symbol: WMATIC,
            token: IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270),
            chainlinkUsdOracle: IAggregatorV2V3(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        aaveRewardsController = IAaveRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
        aaveV2AddressProvider = IPoolAddressesProviderV2(0xd05e3E715d945B59290df0ae8eF85c1BdB684744);
        aaveV2PoolDataProvider = IPoolDataProviderV2(0x7551b5D2763519d4e37e8B81929D336De671d46d);
        nativeUsdOracle = IAggregatorV2V3(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0);
        comet = IComet(0xF25212E676D1F7F89Cd72fFEe66158f541246445);
        cometRewards = ICometRewards(0x45939657d1CA34A8FA39A924B71D28Fe8431e581);
    }

    function init() public override {
        init(forkBlock(Network.Polygon));
    }

    function init(uint256 blockNumber) public virtual override {
        super.init(blockNumber);
        fork("polygon", blockNumber);
        cleanTreasury();
        nativeToken = IWETH9(address(token(WMATIC)));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract MainnetEnv is Env {

    constructor() Env(Network.Mainnet) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_COMPOUND);
        _moneyMarkets.push(MM_SPARK_SKY);
        _moneyMarkets.push(MM_AAVE_V2);
        _moneyMarkets.push(MM_MORPHO_BLUE);
        _moneyMarkets.push(MM_SILO);
        _moneyMarkets.push(MM_AAVE_LIDO);
        _moneyMarkets.push(MM_EULER);
        _moneyMarkets.push(MM_FLUID);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            chainlinkUsdOracle: IAggregatorV2V3(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            chainlinkUsdOracle: IAggregatorV2V3(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9),
            hasPermit: false
        });
        _erc20s[SDAI] = ERC20Data({
            symbol: SDAI,
            token: IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA),
            chainlinkUsdOracle: IAggregatorV2V3(0xb9E6DBFa4De19CCed908BcbFe1d015190678AB5f),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            chainlinkUsdOracle: IAggregatorV2V3(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            chainlinkUsdOracle: IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
            hasPermit: false
        });
        _erc20s[WBTC] = ERC20Data({
            symbol: WBTC,
            token: IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599),
            chainlinkUsdOracle: IAggregatorV2V3(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), // BTC / USD
            hasPermit: false
        });
        _erc20s[RETH] = ERC20Data({
            symbol: RETH,
            token: IERC20(0xae78736Cd615f374D3085123A210448E74Fc6393),
            chainlinkUsdOracle: IAggregatorV2V3(0x05225Cd708bCa9253789C1374e4337a019e99D56),
            hasPermit: false
        });
        _erc20s[GNO] = ERC20Data({
            symbol: GNO,
            token: IERC20(0x6810e776880C02933D47DB1b9fc05908e5386b96),
            chainlinkUsdOracle: IAggregatorV2V3(0x4A7Ad931cb40b564A1C453545059131B126BC828),
            hasPermit: false
        });
        _erc20s[WSTETH] = ERC20Data({
            symbol: WSTETH,
            token: IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0),
            chainlinkUsdOracle: IAggregatorV2V3(0x8B6851156023f4f5A66F68BEA80851c3D905Ac93),
            hasPermit: true
        });
        _erc20s[USDT] = ERC20Data({
            symbol: USDT,
            token: IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7),
            chainlinkUsdOracle: IAggregatorV2V3(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        compoundComptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        compOracle = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
        sparkAddressProvider = IPoolAddressesProvider(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE);
        sparkRewardsController = IAaveRewardsController(0x4370D3b6C9588E02ce9D22e684387859c7Ff5b34);
        aaveV2AddressProvider = IPoolAddressesProviderV2(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
        aaveV2PoolDataProvider = IPoolDataProviderV2(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
        nativeUsdOracle = IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
        siloLens = ISiloLens(0x0e466FC22386997daC23D1f89A43ecb2CB1e76E9);
        wstEthSilo = ISilo(0x4f5717f1EfDec78a960f08871903B394e7Ea95Ed);
    }

    function init() public override {
        init(forkBlock(Network.Mainnet));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("mainnet", blockNumber);
        cleanTreasury();

        aaveAddressProvider = IPoolAddressesProvider(_loadAddress("AavePoolAddressesProvider"));
        aaveRewardsController = IAaveRewardsController(_loadAddress("AaveRewardsController"));
        aaveLidoAddressProvider = IPoolAddressesProvider(_loadAddress("AaveLidoPoolAddressesProvider"));
        aaveLidoRewardsController = IAaveRewardsController(_loadAddress("AaveLidoRewardsController"));

        eulerVaultConnector = IEthereumVaultConnector(_loadAddress("EulerVaultConnector"));
        eulerRewards = IRewardStreams(_loadAddress("EulerRewards"));
        eulerLens = IEulerVaultLens(_loadAddress("EulerVaultLens"));

        fluidVaultResolver = IFluidVaultResolver(_loadAddress("FluidVaultResolver"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), sparkAddressProvider.getPoolDataProvider());

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract GnosisEnv is Env {

    constructor() Env(Network.Gnosis) {
        _moneyMarkets.push(MM_SPARK_SKY);
        _moneyMarkets.push(MM_AAVE);

        // chainlink addresses for gnosis - https://docs.chain.link/data-feeds/price-feeds/addresses?network=gnosis-chain&page=1
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d),
            chainlinkUsdOracle: IAggregatorV2V3(0x678df3415fc31947dA4324eC63212874be5a82f8),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x6A023CCd1ff6F2045C3309768eAd9E68F978f6e1),
            chainlinkUsdOracle: IAggregatorV2V3(0xa767f745331D267c7751297D982b050c93985627),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83),
            chainlinkUsdOracle: IAggregatorV2V3(0x26C31ac71010aF62E6B486D1132E266D6298857D),
            hasPermit: true
        });

        spotStub = new SpotStub(0xf78031CBCA409F2FB6876BDFDBc1b2df24cF9bEf);
        VM.makePersistent(address(spotStub));

        uniswap = 0x4F54dd2F4f30347d841b7783aD08c050d8410a9d;
        uniswapRouter = SwapRouter02(uniswap);
        sparkAddressProvider = IPoolAddressesProvider(0xA98DaCB3fC964A6A0d2ce3B77294241585EAbA6d);
        sparkRewardsController = IAaveRewardsController(0x98e6BcBA7d5daFbfa4a92dAF08d3d7512820c30C);
        aaveAddressProvider = IPoolAddressesProvider(0x36616cf17557639614c1cdDb356b1B83fc0B2132);
        aaveRewardsController = IAaveRewardsController(0xaD4F91D26254B6B0C6346b390dDA2991FDE2F20d);
        nativeUsdOracle = IAggregatorV2V3(0x678df3415fc31947dA4324eC63212874be5a82f8);
    }

    function init() public override {
        init(forkBlock(Network.Gnosis));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        nativeToken = IWETH9(address(token(DAI)));
        fork("gnosis", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, IPoolDataProviderV3(address(0)), sparkAddressProvider.getPoolDataProvider());

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);

        // Gnosis has lower LTV, but some of our tests need a higer one, setting the same as mainnet
        VM.startPrank(0xc4218C1127cB24a0D6c1e7D25dc34e10f2625f5A);
        PoolConfigurator(0x2Fc8823E1b967D474b47Ae0aD041c2ED562ab588).configureReserveAsCollateral({
            asset: address(token(WETH)),
            ltv: 0.8e4,
            liquidationThreshold: 0.825e4,
            liquidationBonus: 1.05e4
        });
        PoolConfigurator(0x2Fc8823E1b967D474b47Ae0aD041c2ED562ab588).configureReserveAsCollateral({
            asset: address(token(DAI)),
            ltv: 0.77e4,
            liquidationThreshold: 0.8e4,
            liquidationBonus: 1.05e4
        });
        VM.stopPrank();
    }

}

contract BaseEnv is Env {

    constructor() Env(Network.Base) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_COMET);
        _moneyMarkets.push(MM_MOONWELL);

        // chainlink addresses for Base - https://docs.chain.link/data-feeds/price-feeds/addresses?network=Base-chain&page=1
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb),
            chainlinkUsdOracle: IAggregatorV2V3(0x591e79239a7d679378eC8c847e5038150364C78F),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x4200000000000000000000000000000000000006),
            chainlinkUsdOracle: IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA),
            chainlinkUsdOracle: IAggregatorV2V3(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
            hasPermit: true
        });
        _erc20s[USDCn] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
            chainlinkUsdOracle: IAggregatorV2V3(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
            hasPermit: true
        });

        spotStub = new SpotStub(0x33128a8fC17869897dcE68Ed026d694621f6FDfD);
        VM.makePersistent(address(spotStub));

        uniswap = 0x2626664c2603336E57B271c5C0b26F421741e481;
        uniswapRouter = SwapRouter02(uniswap);
        aaveAddressProvider = IPoolAddressesProvider(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D);
        aaveRewardsController = IAaveRewardsController(0xf9cc4F0D883F1a1eb2c253bdb46c254Ca51E1F44);
        comet = IComet(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);
        cometRewards = ICometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1);
        moonwellComptroller = IComptroller(0xfBb21d0380beE3312B33c4353c8936a0F13EF26C);
        bridgedMoonwellOracle = 0xffA3F8737C39e36dec4300B162c2153c67c8352f;
        bridgedMoonwellToken = IERC20(0xFF8adeC2221f9f4D8dfbAFa6B9a297d17603493D);
        nativeMoonwellOracle = 0x89D0F320ac73dd7d9513FFC5bc58D1161452a657;
        nativeMoonwellToken = IERC20(0xA88594D404727625A9437C3f886C7643872296AE);
        nativeUsdOracle = IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
    }

    function init() public override {
        init(forkBlock(Network.Base));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("base", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract BscEnv is Env {

    constructor() Env(Network.Bsc) {
        _moneyMarkets.push(MM_AAVE);

        // chainlink addresses for bsc - https://docs.chain.link/data-feeds/price-feeds/addresses?network=bnb-chain&page=1
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3),
            chainlinkUsdOracle: IAggregatorV2V3(0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8),
            chainlinkUsdOracle: IAggregatorV2V3(0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d),
            chainlinkUsdOracle: IAggregatorV2V3(0x51597f405303C4377E36123cBc172b13269EA163),
            hasPermit: false
        });
        _erc20s[WBNB] = ERC20Data({
            symbol: WBNB,
            token: IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c),
            chainlinkUsdOracle: IAggregatorV2V3(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE),
            hasPermit: false
        });
        _erc20s[USDT] = ERC20Data({
            symbol: USDT,
            token: IERC20(0x55d398326f99059fF775485246999027B3197955),
            chainlinkUsdOracle: IAggregatorV2V3(0x0F682319Ed4A240b7a2599A48C965049515D9bC3),
            hasPermit: false
        });

        spotStub = new SpotStub(0x41ff9AA7e16B8B1a8a8dc4f0eFacd93D02d071c9);
        VM.makePersistent(address(spotStub));

        uniswap = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
        uniswapRouter = SwapRouter02(uniswap);
    }

    function init() public override {
        init(forkBlock(Network.Bsc));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        nativeToken = IWETH9(address(token(WBNB)));
        fork("bsc", blockNumber);

        aaveAddressProvider = IPoolAddressesProvider(_loadAddress("AavePoolAddressesProvider"));
        aaveRewardsController = IAaveRewardsController(_loadAddress("AaveRewardsController"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract LineaEnv is Env {

    constructor() Env(Network.Linea) {
        _moneyMarkets.push(MM_ZEROLEND);

        // chainlink addresses for linea - https://docs.chain.link/data-feeds/price-feeds/addresses?network=linea&page=1
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f),
            chainlinkUsdOracle: IAggregatorV2V3(0x3c6Cd9Cc7c7a4c2Cf5a82734CD249D7D593354dA),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff),
            chainlinkUsdOracle: IAggregatorV2V3(0xAADAa473C1bDF7317ec07c915680Af29DeBfdCb5),
            hasPermit: false
        });

        spotStub = new SpotStub(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
        VM.makePersistent(address(spotStub));

        uniswap = 0xb1E835Dc2785b52265711e17fCCb0fd018226a6e;
        uniswapRouter = SwapRouter02(uniswap);
    }

    function init() public override {
        init(forkBlock(Network.Linea));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("linea", blockNumber);

        zeroLendAddressProvider = IPoolAddressesProvider(_loadAddress("ZeroLendPoolAddressesProvider"));
        zeroLendRewardsController = IAaveRewardsController(_loadAddress("ZeroLendRewardsController"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, zeroLendAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract ScrollEnv is Env {

    constructor() Env(Network.Scroll) {
        _moneyMarkets.push(MM_AAVE);

        // chainlink addresses for Scroll - https://docs.chain.link/data-feeds/price-feeds/addresses?network=scroll&page=1
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x5300000000000000000000000000000000000004),
            chainlinkUsdOracle: IAggregatorV2V3(0x6bF14CB0A831078629D993FDeBcB182b21A8774C),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4),
            chainlinkUsdOracle: IAggregatorV2V3(0x43d12Fb3AfCAd5347fA764EeAB105478337b7200),
            hasPermit: false
        });

        spotStub = new SpotStub(0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42);
        VM.makePersistent(address(spotStub));

        uniswap = 0xAAAE99091Fbb28D400029052821653C1C752483B;
        uniswapRouter = SwapRouter02(uniswap);
    }

    function init() public override {
        init(forkBlock(Network.Scroll));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("scroll", blockNumber);

        aaveAddressProvider = IPoolAddressesProvider(_loadAddress("AavePoolAddressesProvider"));
        aaveRewardsController = IAaveRewardsController(_loadAddress("AaveRewardsController"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

contract AvalancheEnv is Env {

    constructor() Env(Network.Avalanche) {
        _moneyMarkets.push(MM_AAVE);

        // chainlink addresses for Avalanche - https://docs.chain.link/data-feeds/price-feeds/addresses?network=Avalanche&page=1
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB),
            chainlinkUsdOracle: IAggregatorV2V3(0x976B3D034E162d8bD72D6b9C989d545b839003b0),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E),
            chainlinkUsdOracle: IAggregatorV2V3(0xF096872672F44d6EBA71458D74fe67F9a77a23B9),
            hasPermit: false
        });

        spotStub = new SpotStub(0x740b1c1de25031C31FF4fC9A62f554A55cdC1baD);
        VM.makePersistent(address(spotStub));

        uniswap = 0x4F54dd2F4f30347d841b7783aD08c050d8410a9d;
        uniswapRouter = SwapRouter02(uniswap);
    }

    function init() public override {
        init(forkBlock(Network.Avalanche));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("avalanche", blockNumber);

        aaveAddressProvider = IPoolAddressesProvider(_loadAddress("AavePoolAddressesProvider"));
        aaveRewardsController = IAaveRewardsController(_loadAddress("AaveRewardsController"));

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        positionNFT = contango.positionNFT();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProviderV3(address(0)));

        erc721Permit2 = new ERC721Permit2();
        VM.prank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(erc721Permit2), true);
        strategyBuilder = deployer.deployStrategyBuilder(this);
    }

}

function fork(string memory name, uint256 blockNumber) {
    if (blockNumber > 0) VM.createSelectFork(name, blockNumber);
    else VM.createSelectFork(name);
}

function signPermit(IERC20 _token, address owner, uint256 ownerPK, address spender, uint256 value)
    returns (EIP2098Permit memory signedPermit)
{
    IERC20Permit permitToken = IERC20Permit(address(_token));

    PermitUtils.Permit memory permit =
        PermitUtils.Permit({ owner: owner, spender: spender, value: value, nonce: permitToken.nonces(owner), deadline: type(uint32).max });

    PermitUtils sigUtils = new PermitUtils(permitToken.DOMAIN_SEPARATOR());
    (uint8 v, bytes32 r, bytes32 s) = VM.sign(ownerPK, sigUtils.getTypedDataHash(permit));

    signedPermit.r = r;
    signedPermit.vs = _encode(s, v);

    signedPermit.amount = value;
    signedPermit.deadline = permit.deadline;
}

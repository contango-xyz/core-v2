// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "src/core/Contango.sol";
import "src/core/OrderManager.sol";
import "src/core/Maestro.sol";
import "src/core/Vault.sol";
import "src/dependencies/IWETH9.sol";
import "src/interfaces/IOrderManager.sol";
import "src/core/ReferralManager.sol";
import "src/core/FeeManager.sol";

import "test/flp/balancer/BalancerFlashLoanProvider.sol";
import "test/flp/aave/AaveFlashLoanProvider.sol";

import "src/moneymarkets/UnderlyingPositionFactory.sol";
import "src/moneymarkets/UpgradeableBeaconWithOwner.sol";
import "src/moneymarkets/ImmutableBeaconProxy.sol";
import "src/moneymarkets/aave/AaveMoneyMarket.sol";
import "src/moneymarkets/aave/AaveV2MoneyMarket.sol";
import "src/moneymarkets/aave/AaveMoneyMarketView.sol";
import "src/moneymarkets/aave/AgaveMoneyMarket.sol";
import "src/moneymarkets/aave/AgaveMoneyMarketView.sol";
import "src/moneymarkets/aave/SparkMoneyMarket.sol";
import "src/moneymarkets/aave/SparkMoneyMarketView.sol";
import "src/moneymarkets/aave/GranaryMoneyMarketView.sol";
import "src/moneymarkets/aave/dependencies/IPoolAddressesProviderV2.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarket.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarketView.sol";
import "src/moneymarkets/compound/CompoundMoneyMarket.sol";
import "src/moneymarkets/compound/CompoundMoneyMarketView.sol";
import "src/moneymarkets/compound/SonneMoneyMarketView.sol";
import "src/moneymarkets/compound/LodestarMoneyMarket.sol";
import "src/moneymarkets/compound/LodestarMoneyMarketView.sol";
import "src/moneymarkets/comet/CometMoneyMarket.sol";
import "src/moneymarkets/comet/CometMoneyMarketView.sol";
import "src/moneymarkets/compound/MoonwellMoneyMarket.sol";
import "src/moneymarkets/compound/MoonwellMoneyMarketView.sol";
import "src/moneymarkets/morpho/MorphoBlueMoneyMarket.sol";
import "src/moneymarkets/morpho/MorphoBlueMoneyMarketView.sol";
import "src/moneymarkets/silo/SiloMoneyMarket.sol";
import "src/moneymarkets/silo/SiloMoneyMarketView.sol";
import "src/moneymarkets/ContangoLens.sol";
import "src/models/FixedFeeModel.sol";

import "script/constants.sol";

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

Vm constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

uint256 constant TRADER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
address payable constant TRADER = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
uint256 constant TRADER2_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
address payable constant TRADER2 = payable(address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8));
address payable constant TREASURY = payable(0x643178CF8AEc063962654CAc256FD1f7fe06ac28);
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

uint256 constant DEFAULT_TRADING_FEE = 0.001e18; // 0.1%
uint256 constant DEFAULT_ORACLE_UNIT = 1e8;

bytes32 constant DEFAULT_ADMIN_ROLE = "";

Symbol constant WETHUSDC = Symbol.wrap("WETHUSDC");

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
    else if (network == Network.Goerli) return Env(_deployCode("TestSetup.t.sol:GoerliEnv"));
    else if (network == Network.Gnosis) return Env(_deployCode("TestSetup.t.sol:GnosisEnv"));
    else if (network == Network.Base) return Env(_deployCode("TestSetup.t.sol:BaseEnv"));
    else revert(string.concat("Unsupported network: ", network.toString()));
}

function forkBlock(Network network) pure returns (uint256) {
    if (network == Network.Arbitrum) return 98_674_994;
    else if (network == Network.Optimism) return 107_312_284;
    else if (network == Network.Polygon) return 45_578_550;
    else if (network == Network.Mainnet) return 18_012_703;
    else if (network == Network.Goerli) return 10_070_880;
    else if (network == Network.Gnosis) return 30_772_017;
    else if (network == Network.Base) return 6_372_881;
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

function tradingFee(uint256 quantity, uint256 fee) pure returns (uint256) {
    return Math.mulDiv(quantity, fee, 1e18);
}

function tradingFee(uint256 quantity, uint256 fee, Math.Rounding rounding) pure returns (uint256) {
    return Math.mulDiv(quantity, fee, 1e18, rounding);
}

function tradingFee(uint256 quantity) pure returns (uint256) {
    return Math.mulDiv(quantity, DEFAULT_TRADING_FEE, 1e18);
}

function discountFee(uint256 quantity) pure returns (uint256) {
    return quantity - tradingFee(quantity);
}

/// @dev returns the init code (creation code + ABI-encoded args) used in CREATE2
/// @param creationCode the creation code of a contract C, as returned by type(C).creationCode
/// @param args the ABI-encoded arguments to the constructor of C
function initCode(bytes memory creationCode, bytes memory args) pure returns (bytes memory) {
    return abi.encodePacked(creationCode, args);
}

struct Deployment {
    Maestro maestro;
    IVault vault;
    Contango contango;
    ContangoLens contangoLens;
    IOrderManager orderManager;
    IFeeManager feeManager;
    TSQuoter tsQuoter;
}

contract Deployer {

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    function deployAaveMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveMoneyMarket(
            contango,
            MM_AAVE,
            env.aaveAddressProvider().getPool(),
            env.aaveAddressProvider().getPoolDataProvider(),
            env.aaveRewardsController()
        );
    }

    function deployAaveMoneyMarket(
        IContango contango,
        MoneyMarketId mmId,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AaveMoneyMarket({
            _moneyMarketId: mmId,
            _contango: contango,
            _pool: _pool,
            _dataProvider: _dataProvider,
            _rewardsController: _rewardsController
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployAaveV2MoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveV2MoneyMarket(
            contango,
            MM_AAVE_V2,
            IPool(env.aaveV2AddressProvider().getLendingPool()),
            IPoolDataProvider(address(0)),
            IAaveRewardsController(address(0))
        );
    }

    function deployAgaveMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AgaveMoneyMarket({
            _moneyMarketId: MM_AGAVE,
            _contango: contango,
            _pool: IPool(env.agaveAddressProvider().getLendingPool()),
            _dataProvider: IPoolDataProvider(address(0)),
            _rewardsController: IAaveRewardsController(0xfa255f5104f129B78f477e9a6D050a02f31A5D86)
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployRadiantMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveV2MoneyMarket(
            contango,
            MM_RADIANT,
            IPool(env.radiantAddressProvider().getLendingPool()),
            IPoolDataProvider(address(0)),
            IAaveRewardsController(address(0))
        );
    }

    function deployGranaryMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        return deployAaveV2MoneyMarket(
            contango,
            MM_GRANARY,
            IPool(env.granaryAddressProvider().getLendingPool()),
            IPoolDataProvider(address(0)),
            IAaveRewardsController(address(env.granaryRewardsController()))
        );
    }

    function deployAaveV2MoneyMarket(
        IContango contango,
        MoneyMarketId mmId,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AaveV2MoneyMarket({
            _moneyMarketId: mmId,
            _contango: contango,
            _pool: _pool,
            _dataProvider: _dataProvider,
            _rewardsController: _rewardsController
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deploySparkMoneyMarket(Env env, IContango contango) public returns (SparkMoneyMarket moneyMarket) {
        moneyMarket = new SparkMoneyMarket({
            _moneyMarketId: MM_SPARK,
            _contango: contango,
            _pool: env.sparkAddressProvider().getPool(),
            _dataProvider: env.sparkAddressProvider().getPoolDataProvider(),
            _rewardsController: IAaveRewardsController(address(0)),
            _dai: env.token(DAI),
            _sDAI: ISDAI(address(env.token(SDAI))),
            _usdc: env.token(USDC),
            _psm: IDssPsm(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A)
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = SparkMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deploySparkMoneyMarketGnosis(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = deployAaveMoneyMarket(
            contango,
            MM_SPARK,
            env.sparkAddressProvider().getPool(),
            env.sparkAddressProvider().getPoolDataProvider(),
            IAaveRewardsController(address(0))
        );
    }

    function deployExactlyMoneyMarket(Env env, IContango contango) public returns (ExactlyMoneyMarket moneyMarket) {
        moneyMarket = new ExactlyMoneyMarket({
            _moneyMarketId: MM_EXACTLY,
            _contango: contango,
            _reverseLookup: new ExactlyReverseLookup(TIMELOCK, env.auditor()),
            _rewardsController: IExactlyRewardsController(0xBd1ba78A3976cAB420A9203E6ef14D18C2B2E031)
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = ExactlyMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployCometMoneyMarket(Env env, IContango contango) public returns (CometMoneyMarket moneyMarket) {
        IComet[] memory comets = new IComet[](1);
        comets[0] = env.comet();
        CometReverseLookup reverseLookup = new CometReverseLookup(TIMELOCK, comets);
        moneyMarket = new CometMoneyMarket({
            _moneyMarketId: MM_COMET,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _rewards: env.cometRewards()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = CometMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployCompoundMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(TIMELOCK, env.compoundComptroller(), env.nativeToken());
        reverseLookup.update();
        moneyMarket = new CompoundMoneyMarket({
            _moneyMarketId: MM_COMPOUND,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deploySonneMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(TIMELOCK, env.compoundComptroller(), env.nativeToken());
        reverseLookup.update();
        moneyMarket = new CompoundMoneyMarket({
            _moneyMarketId: MM_SONNE,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: IWETH9(address(0))
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployMoonwellMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(TIMELOCK, env.moonwellComptroller(), env.nativeToken());
        reverseLookup.update();
        moneyMarket = new MoonwellMoneyMarket({
            _moneyMarketId: MM_MOONWELL,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken()
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployLodestarMoneyMarket(Env env, IContango contango) public returns (CompoundMoneyMarket moneyMarket) {
        CompoundReverseLookup reverseLookup = new CompoundReverseLookup(TIMELOCK, env.compoundComptroller(), env.nativeToken());
        reverseLookup.update();
        moneyMarket = new LodestarMoneyMarket({
            _moneyMarketId: MM_LODESTAR,
            _contango: contango,
            _reverseLookup: reverseLookup,
            _nativeToken: env.nativeToken(),
            _arbToken: env.token(ARB)
        });
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = CompoundMoneyMarket(payable(address(new ImmutableBeaconProxy(beacon))));
    }

    function deployMorphoBlueMoneyMarket(Env env, IContango contango) public returns (MorphoBlueMoneyMarket moneyMarket) {
        moneyMarket = new MorphoBlueMoneyMarket({
            _moneyMarketId: MM_MORPHO_BLUE,
            _contango: contango,
            _morpho: env.morpho(),
            _reverseLookup: new MorphoBlueReverseLookup(TIMELOCK, env.morpho())
        });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = MorphoBlueMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deploySiloMoneyMarket(Env, IContango contango) public returns (SiloMoneyMarket moneyMarket) {
        moneyMarket = new SiloMoneyMarket({ _contango: contango });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = SiloMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployVault(Env env) public returns (Vault vault) {
        vault = new Vault(env.nativeToken());
        vault.initialize(TIMELOCK);
        VM.label(address(vault), "Vault");
    }

    function deployContango(Env env) public returns (Deployment memory deployment) {
        PositionNFT positionNFT = new PositionNFT(TIMELOCK);
        UnderlyingPositionFactory positionFactory = new UnderlyingPositionFactory(TIMELOCK);

        deployment.vault = deployVault(env);
        deployment.contangoLens = new ContangoLens();
        ContangoLens(address(deployment.contangoLens)).initialize(TIMELOCK);

        deployment.feeManager = new FeeManager({
            _treasury: TREASURY,
            _vault: deployment.vault,
            _feeModel: new FixedFeeModel(TIMELOCK),
            _referralManager: new ReferralManager(TIMELOCK)
        });
        FeeManager(address(deployment.feeManager)).initialize(TIMELOCK);

        deployment.contango = new Contango(positionNFT, deployment.vault, positionFactory, deployment.feeManager, new SpotExecutor());
        Contango(payable(address(deployment.contango))).initialize(TIMELOCK);

        deployment.tsQuoter = new TSQuoter(Contango(payable(address(deployment.contango))), deployment.contangoLens);

        VM.startPrank(TIMELOCK_ADDRESS);
        FixedFeeModel(address(deployment.feeManager.feeModel())).setDefaultFee(DEFAULT_TRADING_FEE);

        positionFactory.grantRole(CONTANGO_ROLE, address(deployment.contango));

        if (env.marketAvailable(MM_AAVE)) {
            positionFactory.registerMoneyMarket(deployAaveMoneyMarket(env, deployment.contango));
            deployment.contangoLens.setMoneyMarketView(
                new AaveMoneyMarketView(
                    MM_AAVE,
                    "AaveV3",
                    deployment.contango,
                    env.aaveAddressProvider().getPool(),
                    env.aaveAddressProvider().getPoolDataProvider(),
                    env.aaveAddressProvider().getPriceOracle(),
                    env.nativeToken(),
                    env.nativeUsdOracle()
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
        if (env.marketAvailable(MM_SPARK)) {
            if (env.network().isMainnet()) {
                positionFactory.registerMoneyMarket(deploySparkMoneyMarket(env, deployment.contango));
                deployment.contangoLens.setMoneyMarketView(
                    new SparkMoneyMarketView(
                        deployment.contango,
                        env.sparkAddressProvider().getPool(),
                        env.sparkAddressProvider().getPoolDataProvider(),
                        env.sparkAddressProvider().getPriceOracle(),
                        env.token(DAI),
                        ISDAI(address(env.token(SDAI))),
                        env.token(USDC),
                        env.nativeToken(),
                        env.nativeUsdOracle()
                    )
                );
            }
            if (env.network().isGnosis()) {
                positionFactory.registerMoneyMarket(deploySparkMoneyMarketGnosis(env, deployment.contango));
                deployment.contangoLens.setMoneyMarketView(
                    new AaveMoneyMarketView(
                        MM_SPARK,
                        "Spark",
                        deployment.contango,
                        env.sparkAddressProvider().getPool(),
                        env.sparkAddressProvider().getPoolDataProvider(),
                        env.sparkAddressProvider().getPriceOracle(),
                        env.nativeToken(),
                        env.nativeUsdOracle()
                    )
                );
            }
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
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_AGAVE)) {
            positionFactory.registerMoneyMarket(deployAgaveMoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new AgaveMoneyMarketView(
                    deployment.contango,
                    IPool(env.agaveAddressProvider().getLendingPool()),
                    env.agavePoolDataProvider(),
                    IAaveOracle(env.agaveAddressProvider().getPriceOracle()),
                    env.nativeToken(),
                    env.nativeUsdOracle()
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
                    IPool(env.aaveV2AddressProvider().getLendingPool()),
                    env.aaveV2PoolDataProvider(),
                    IAaveOracle(env.aaveV2AddressProvider().getPriceOracle()),
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
                    IPool(env.radiantAddressProvider().getLendingPool()),
                    env.radiantPoolDataProvider(),
                    IAaveOracle(env.radiantAddressProvider().getPriceOracle()),
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
                new LodestarMoneyMarketView(
                    deployment.contango,
                    moneyMarket.reverseLookup(),
                    env.lodestarOracle(),
                    env.erc20(ARB).chainlinkUsdOracle,
                    env.token(ARB),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_MOONWELL)) {
            CompoundMoneyMarket moneyMarket = deployMoonwellMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new MoonwellMoneyMarketView(
                    deployment.contango, moneyMarket.reverseLookup(), env.moonwellOracle(), env.moonwellToken(), env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_COMET)) {
            CometMoneyMarket moneyMarket = deployCometMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.contangoLens.setMoneyMarketView(
                new CometMoneyMarketView(
                    deployment.contango,
                    env.nativeToken(),
                    env.nativeUsdOracle(),
                    moneyMarket.reverseLookup(),
                    env.cometRewards(),
                    IAggregatorV2V3(env.compOracle())
                )
            );
        }
        if (env.marketAvailable(MM_GRANARY)) {
            positionFactory.registerMoneyMarket(deployGranaryMoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new GranaryMoneyMarketView(
                    deployment.contango,
                    IPool(env.granaryAddressProvider().getLendingPool()),
                    env.granaryPoolDataProvider(),
                    IAaveOracle(env.granaryAddressProvider().getPriceOracle()),
                    env.nativeToken(),
                    env.nativeUsdOracle()
                )
            );
        }
        if (env.marketAvailable(MM_SILO)) {
            positionFactory.registerMoneyMarket(deploySiloMoneyMarket(env, deployment.contango));

            deployment.contangoLens.setMoneyMarketView(
                new SiloMoneyMarketView(deployment.contango, env.nativeToken(), env.nativeUsdOracle())
            );
        }

        VM.stopPrank();

        VM.startPrank(TIMELOCK_ADDRESS);
        positionNFT.grantRole(MINTER_ROLE, address(deployment.contango));

        // Flash loan providers
        {
            IERC7399 balancerFLP = new BalancerFlashLoanProvider(IFlashLoaner(env.balancer()));
            deployment.tsQuoter.addFlashLoanProvider(balancerFLP);
            env.setBalancerFLP(balancerFLP);

            if (env.marketAvailable(MM_AAVE)) {
                IERC7399 aaveFLP = new AaveFlashLoanProvider(env.aaveAddressProvider());
                deployment.tsQuoter.addFlashLoanProvider(aaveFLP);
                env.setAaveFLP(aaveFLP);
            }
        }

        VM.stopPrank();

        deployment.orderManager = new OrderManager(deployment.contango);
        OrderManager(payable(address(deployment.orderManager))).initialize({
            timelock: TIMELOCK,
            _gasMultiplier: 2e4,
            _gasTip: 0,
            _oracle: deployment.contangoLens
        });

        deployment.maestro =
            new Maestro(TIMELOCK, deployment.contango, deployment.orderManager, deployment.vault, env.permit2(), new SimpleSpotExecutor());
        VM.label(address(deployment.maestro), "Maestro");

        VM.startPrank(TIMELOCK_ADDRESS);
        positionNFT.setContangoContract(address(deployment.maestro), true);
        positionNFT.setContangoContract(address(deployment.orderManager), true);
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.maestro));
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.contango));
        AccessControl(address(deployment.vault)).grantRole(CONTANGO_ROLE, address(deployment.orderManager));
        AccessControl(address(deployment.feeManager)).grantRole(CONTANGO_ROLE, address(deployment.contango));
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
    else if (mmId == MoneyMarketId.unwrap(MM_SPARK)) return "Spark";
    else if (mmId == MoneyMarketId.unwrap(MM_MORPHO_BLUE)) return "MorphoBlue";
    else if (mmId == MoneyMarketId.unwrap(MM_AGAVE)) return "Agave";
    else if (mmId == MoneyMarketId.unwrap(MM_AAVE_V2)) return "AaveV2";
    else if (mmId == MoneyMarketId.unwrap(MM_RADIANT)) return "Radiant";
    else revert(string.concat("Unsupported money market: ", VM.toString(mmId)));
}

abstract contract Env is StdAssertions, StdCheats {

    // Aave
    IPoolAddressesProvider public aaveAddressProvider;
    IAaveRewardsController public aaveRewardsController;
    // Aave V2
    IPoolAddressesProviderV2 public aaveV2AddressProvider;
    IPoolDataProvider public aaveV2PoolDataProvider;
    // Radiant
    IPoolAddressesProviderV2 public radiantAddressProvider;
    IPoolDataProvider public radiantPoolDataProvider;
    // Compound
    IComptroller public compoundComptroller;
    address public compOracle;
    // Exactly
    IAuditor public auditor;
    IExactlyPreviewer public previewer;
    // Spark
    IPoolAddressesProvider public sparkAddressProvider;
    // Agave
    IPoolAddressesProviderV2 public agaveAddressProvider;
    IPoolDataProvider public agavePoolDataProvider;
    // Morpho
    IMorpho public morpho;
    // Uniswap
    address public uniswap;
    SwapRouter02 public uniswapRouter;
    // Balancer
    address public balancer;
    // Sonne
    address public sonneOracle;
    // Lodestar
    address public lodestarOracle;
    // Comet
    IComet public comet;
    ICometRewards public cometRewards;
    // Moonwell
    IComptroller public moonwellComptroller;
    address public moonwellOracle;
    IERC20 public moonwellToken;
    // Granary
    IPoolAddressesProviderV2 public granaryAddressProvider;
    IPoolDataProvider public granaryPoolDataProvider;
    IGranaryRewarder public granaryRewardsController;
    // Test
    SpotStub public spotStub;
    PositionActions public positionActions;
    PositionActions public positionActions2;
    // Contango
    Contango public contango;
    IVault public vault;
    Maestro public maestro;
    IOrderManager public orderManager;
    IUnderlyingPositionFactory public positionFactory;
    IFeeManager public feeManager;
    Encoder public encoder;
    TSQuoter public tsQuoter;
    ContangoLens public contangoLens;
    // Chain
    IWETH9 public nativeToken;
    IAggregatorV2V3 public nativeUsdOracle;
    // MultiChain
    IPermit2 public permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // FlashLoanProviders
    IERC7399 public balancerFLP;
    IERC7399 public aaveFLP;

    Network public network;
    Deployer public deployer;
    MoneyMarketId[] internal _moneyMarkets;
    MoneyMarketId[] internal _fuzzMoneyMarkets;
    IERC7399[] internal _flashLoanProviders;
    mapping(bytes32 => ERC20Data) internal _erc20s;
    mapping(bytes32 => ERC20Bounds) internal _bounds;
    mapping(Symbol => TestInstrument) public _instruments;

    uint256 public blockNumber;

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
        _bounds[WETH] = ERC20Bounds({ min: 0.1e18, max: type(uint96).max, dust: 0.0000001e18 });
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

    function setAaveFLP(IERC7399 flp) public {
        aaveFLP = flp;
        _flashLoanProviders.push(flp);
    }

    function setBalancerFLP(IERC7399 flp) public {
        balancerFLP = flp;
        _flashLoanProviders.push(flp);
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

    function assertNoBalances(IERC20 _token, address addr, uint256 dust, string memory label) public {
        uint256 balance = address(_token) == address(0) ? addr.balance : _token.balanceOf(addr);
        assertApproxEqAbsDecimal(balance, 0, dust, _token.decimals(), label);
    }

    function checkInvariants(TestInstrument memory instrument, PositionId positionId, IERC7399 flp) public {
        assertNoBalances(instrument, positionId, flp);
    }

    function checkInvariants(TestInstrument memory instrument, PositionId positionId, IERC7399 flp, uint256 contangoBaseTolerance) public {
        assertNoBalances(instrument, positionId, flp, contangoBaseTolerance);
    }

    function assertNoBalances(TestInstrument memory instrument, PositionId positionId, IERC7399 flp) public {
        assertNoBalances(instrument, positionId, flp, bounds(instrument.baseData.symbol).dust);
    }

    function assertNoBalances(TestInstrument memory instrument, PositionId positionId, IERC7399 flp, uint256 contangoBaseTolerance)
        public
    {
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
        if (address(flp) != address(0)) {
            assertNoBalances(
                instrument.base,
                address(flp),
                bounds(instrument.baseData.symbol).dust,
                string.concat("FLP (", VM.toString(address(flp)), ") balance: base")
            );
            assertNoBalances(
                instrument.quote,
                address(flp),
                bounds(instrument.quoteData.symbol).dust,
                string.concat("FLP (", VM.toString(address(flp)), ") balance: quote")
            );
        }
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
        IERC20Permit permitToken = IERC20Permit(address(_token));

        PermitUtils.Permit memory permit =
            PermitUtils.Permit({ owner: to, spender: approveTo, value: amount, nonce: permitToken.nonces(to), deadline: type(uint32).max });

        PermitUtils sigUtils = new PermitUtils(permitToken.DOMAIN_SEPARATOR());
        (uint8 v, bytes32 r, bytes32 s) = VM.sign(toPk, sigUtils.getTypedDataHash(permit));

        signedPermit.r = r;
        signedPermit.vs = _encode(s, v);

        signedPermit.amount = amount;
        signedPermit.deadline = permit.deadline;
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

}

contract ArbitrumEnv is Env {

    constructor() Env(Network.Arbitrum) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_RADIANT);
        _moneyMarkets.push(MM_LODESTAR);
        _moneyMarkets.push(MM_SILO);

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
            chainlinkUsdOracle: IAggregatorV2V3(0x6ce185860a4963106506C203335A2910413708e9),
            hasPermit: true
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        radiantAddressProvider = IPoolAddressesProviderV2(0x091d52CacE1edc5527C99cDCFA6937C1635330E4);
        radiantPoolDataProvider = IPoolDataProvider(0x596B0cc4c5094507C50b579a662FE7e7b094A2cC);
        compoundComptroller = IComptroller(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
        lodestarOracle = 0x49bB23DfAe944059C2403BCc255c5a9c0F851a8D;
        nativeUsdOracle = IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
    }

    function init() public override {
        init(forkBlock(Network.Arbitrum));
    }

    function init(uint256 blockNumber) public virtual override {
        super.init(blockNumber);
        fork("arbitrum", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProvider(address(0)));
    }

}

contract OptimismEnv is Env {

    constructor() Env(Network.Optimism) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_EXACTLY);
        _moneyMarkets.push(MM_SONNE);
        _moneyMarkets.push(MM_GRANARY);

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

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        auditor = IAuditor(0xaEb62e6F27BC103702E7BC879AE98bceA56f027E);
        previewer = IExactlyPreviewer(0xb8b1f590272b541b263A49b28bF52f8774b0E6c9);
        compoundComptroller = IComptroller(0x60CF091cD3f50420d50fD7f707414d0DF4751C58);
        sonneOracle = 0x4E60495550071693bc8bDfFC40033d278157EAC7;
        granaryAddressProvider = IPoolAddressesProviderV2(0xdDE5dC81e40799750B92079723Da2acAF9e1C6D6);
        granaryPoolDataProvider = IPoolDataProvider(0x9546F673eF71Ff666ae66d01Fd6E7C6Dae5a9995);
        granaryRewardsController = IGranaryRewarder(0x6A0406B8103Ec68EE9A713A073C7bD587c5e04aD);
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
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProvider(address(0)));
    }

}

contract PolygonEnv is Env {

    constructor() Env(Network.Polygon) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_AAVE_V2);

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
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        aaveRewardsController = IAaveRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
        aaveV2AddressProvider = IPoolAddressesProviderV2(0xd05e3E715d945B59290df0ae8eF85c1BdB684744);
        aaveV2PoolDataProvider = IPoolDataProvider(0x7551b5D2763519d4e37e8B81929D336De671d46d);
        nativeUsdOracle = IAggregatorV2V3(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0);
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
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProvider(address(0)));
    }

}

contract MainnetEnv is Env {

    constructor() Env(Network.Mainnet) {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_COMPOUND);
        _moneyMarkets.push(MM_SPARK);
        _moneyMarkets.push(MM_AAVE_V2);

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

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
        compoundComptroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        compOracle = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
        sparkAddressProvider = IPoolAddressesProvider(0x02C3eA4e34C0cBd694D2adFa2c690EECbC1793eE);
        aaveV2AddressProvider = IPoolAddressesProviderV2(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
        aaveV2PoolDataProvider = IPoolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
        nativeUsdOracle = IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }

    function init() public override {
        init(forkBlock(Network.Mainnet));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("mainnet", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), sparkAddressProvider.getPoolDataProvider());
    }

}

contract GoerliEnv is Env {

    constructor() Env(Network.Goerli) {
        _moneyMarkets.push(MM_MORPHO_BLUE);

        // chainlink addresses for goerli - https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=#goerli-testnet
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x0aCd15Fb54034492c392596B56ED415bD07e70d7),
            chainlinkUsdOracle: IAggregatorV2V3(0x0d79df66BE487753B02D015Fb622DED7f0E9798d),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x62bD2A599664D421132d7C54AB4DbE3233f4f0Ae),
            chainlinkUsdOracle: IAggregatorV2V3(0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7),
            hasPermit: false
        });
        _erc20s[USDT] = ERC20Data({
            symbol: USDT,
            token: IERC20(0x576e379FA7B899b4De1E251e935B31543Df3e954),
            chainlinkUsdOracle: IAggregatorV2V3(0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6),
            chainlinkUsdOracle: IAggregatorV2V3(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        compoundComptroller = IComptroller(0x05Df6C772A563FfB37fD3E04C1A279Fb30228621);
        morpho = IMorpho(0x64c7044050Ba0431252df24fEd4d9635a275CB41);
        nativeUsdOracle = IAggregatorV2V3(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
    }

    function init() public override {
        init(forkBlock(Network.Goerli));
    }

    function init(uint256 blockNumber) public override {
        super.init(blockNumber);
        fork("goerli", blockNumber);
        cleanTreasury();

        Deployment memory deployment = deployer.deployContango(this);
        maestro = deployment.maestro;
        vault = deployment.vault;
        contango = deployment.contango;
        contangoLens = deployment.contangoLens;
        orderManager = deployment.orderManager;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(address(0)), IPoolDataProvider(address(0)));
    }

}

contract GnosisEnv is Env {

    constructor() Env(Network.Gnosis) {
        _moneyMarkets.push(MM_SPARK);
        _moneyMarkets.push(MM_AGAVE);
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
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        sparkAddressProvider = IPoolAddressesProvider(0xA98DaCB3fC964A6A0d2ce3B77294241585EAbA6d);
        agaveAddressProvider = IPoolAddressesProviderV2(0x3673C22153E363B1da69732c4E0aA71872Bbb87F);
        agavePoolDataProvider = IPoolDataProvider(0xE6729389DEa76D47b5BcB0bA5c080821c3B51329);
        aaveAddressProvider = IPoolAddressesProvider(0x36616cf17557639614c1cdDb356b1B83fc0B2132);
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
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(address(0)), sparkAddressProvider.getPoolDataProvider());

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
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D);
        comet = IComet(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);
        cometRewards = ICometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1);
        compOracle = 0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428;
        moonwellComptroller = IComptroller(0xfBb21d0380beE3312B33c4353c8936a0F13EF26C);
        moonwellOracle = 0xffA3F8737C39e36dec4300B162c2153c67c8352f;
        moonwellToken = IERC20(0xFF8adeC2221f9f4D8dfbAFa6B9a297d17603493D);
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
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, aaveAddressProvider.getPoolDataProvider(), IPoolDataProvider(address(0)));
    }

}

function fork(string memory name, uint256 blockNumber) {
    if (blockNumber > 0) VM.createSelectFork(name, blockNumber);
    else VM.createSelectFork(name);
}

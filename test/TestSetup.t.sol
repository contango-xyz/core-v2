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
import "src/moneymarkets/aave/AaveMoneyMarketView.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarket.sol";
import "src/moneymarkets/exactly/ExactlyMoneyMarketView.sol";
import "src/oracle/AaveOracle.sol";
import "src/models/FixedFeeModel.sol";

import "script/constants.sol";

import "./dependencies/chainlink/AggregatorV2V3Interface.sol";
import "./dependencies/Uniswap.sol";
import "./stub/NoFeeModel.sol";
import { PositionActions } from "./PositionActions.sol";
import "./Encoder.sol";
import "./SpotStub.sol";
import "./TestHelper.sol";
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

function provider(Network network) returns (Env) {
    if (network == Network.Arbitrum) return new ArbitrumEnv();
    else if (network == Network.Optimism) return new OptimismEnv();
    else if (network == Network.Polygon) return new PolygonEnv();
    else if (network == Network.Mainnet) return new MainnetEnv();
    else revert(string.concat("Unsupported network: ", network.toString()));
}

function forkBlock(Network network) pure returns (uint256) {
    if (network == Network.Arbitrum) return 98_674_994;
    else if (network == Network.Optimism) return 107_312_284;
    else if (network == Network.Polygon) return 45_578_550;
    else if (network == Network.Mainnet) return 18_012_703;
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
    AggregatorV2V3Interface chainlinkUsdOracle;
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
    IOrderManager orderManager;
    IOracle oracle;
    IFeeManager feeManager;
    TSQuoter tsQuoter;
}

contract Deployer {

    // Ignore this contract for size verification
    bool public constant IS_TEST = true;

    function deployAaveMoneyMarket(Env env, IContango contango) public returns (AaveMoneyMarket moneyMarket) {
        moneyMarket = new AaveMoneyMarket({
                _moneyMarketId: MM_AAVE,
                _contango: contango,
                _provider: env.aaveAddressProvider(),
                _rewardsController: env.aaveRewardsController()
            });

        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = AaveMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
    }

    function deployExactlyMoneyMarket(Env env, IContango contango) public returns (ExactlyMoneyMarket moneyMarket) {
        moneyMarket = new ExactlyMoneyMarket({
            _moneyMarketId: MM_EXACTLY,
            _contango: contango,
            _reverseLookup: new ExactlyReverseLookup(TIMELOCK, env.auditor()),
            _rewardsController: IExactlyRewardsController(0xBd1ba78A3976cAB420A9203E6ef14D18C2B2E031)}
        );
        UpgradeableBeacon beacon = new UpgradeableBeaconWithOwner(address(moneyMarket), address(this));
        moneyMarket = ExactlyMoneyMarket(address(new ImmutableBeaconProxy(beacon)));
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

        deployment.feeManager = new FeeManager({
            _treasury: TREASURY,
            _vault: deployment.vault,
            _feeModel: new FixedFeeModel(DEFAULT_TRADING_FEE),
            _referralManager: new ReferralManager(TIMELOCK)
        });
        FeeManager(address(deployment.feeManager)).initialize(TIMELOCK);

        deployment.contango = new Contango(positionNFT, deployment.vault, positionFactory, deployment.feeManager, new SpotExecutor());
        Contango(payable(address(deployment.contango))).initialize(TIMELOCK);

        deployment.tsQuoter = new TSQuoter(Contango(payable(address(deployment.contango))));

        VM.startPrank(TIMELOCK_ADDRESS);
        positionFactory.grantRole(CONTANGO_ROLE, address(deployment.contango));

        if (env.marketAvailable(MM_AAVE)) {
            positionFactory.registerMoneyMarket(deployAaveMoneyMarket(env, deployment.contango));
            deployment.tsQuoter.setMoneyMarket(new AaveMoneyMarketView(MM_AAVE, env.aaveAddressProvider(), positionFactory));
        }
        if (env.marketAvailable(MM_EXACTLY)) {
            ExactlyMoneyMarket moneyMarket = deployExactlyMoneyMarket(env, deployment.contango);
            positionFactory.registerMoneyMarket(moneyMarket);
            deployment.tsQuoter.setMoneyMarket(
                new ExactlyMoneyMarketView(MM_EXACTLY, moneyMarket.reverseLookup(), env.auditor(), positionFactory)
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

        deployment.orderManager = new OrderManager(deployment.contango, env.nativeToken());
        deployment.oracle = new AaveOracle(env.aaveAddressProvider());
        OrderManager(payable(address(deployment.orderManager))).initialize({
            timelock: TIMELOCK,
            _gasMultiplier: 2e4,
            _gasTip: 0,
            _oracle: deployment.oracle
        });

        deployment.maestro = new Maestro(TIMELOCK, deployment.contango,deployment. orderManager,deployment. vault, env.permit2());
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
    if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_AAVE)) return "Aave";
    else if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_EXACTLY)) return "Exactly";
    else revert("Unsupported money market");
}

abstract contract Env is StdAssertions, StdCheats {

    // Aave
    IPoolAddressesProvider public aaveAddressProvider;
    IAaveRewardsController public aaveRewardsController;
    // Exactly
    IAuditor public auditor;
    // Uniswap
    address public uniswap;
    SwapRouter02 public uniswapRouter;
    // Balancer
    address public balancer;
    // Test
    SpotStub public spotStub;
    PositionActions public positionActions;
    PositionActions public positionActions2;
    TestHelper public helper;
    NoFeeModel public noFeeModel;
    // Contango
    Contango public contango;
    IVault public vault;
    Maestro public maestro;
    IOrderManager public orderManager;
    IUnderlyingPositionFactory public positionFactory;
    IOracle public oracle;
    IFeeManager public feeManager;
    Encoder public encoder;
    TSQuoter public tsQuoter;
    // Chain
    IWETH9 public nativeToken;
    // MultiChain
    IPermit2 public permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // FlashLoanProviders
    IERC7399 public balancerFLP;
    IERC7399 public aaveFLP;

    Deployer public deployer;
    MoneyMarketId[] internal _moneyMarkets;
    IERC7399[] internal _flashLoanProviders;
    mapping(bytes32 => ERC20Data) internal _erc20s;
    mapping(bytes32 => ERC20Bounds) internal _bounds;
    mapping(Symbol => TestInstrument) public _instruments;

    constructor() {
        VM.makePersistent(address(this));

        deployer = new Deployer();
        VM.makePersistent(address(deployer));

        helper = new TestHelper();
        VM.makePersistent(address(helper));

        noFeeModel = new NoFeeModel();
        VM.makePersistent(address(noFeeModel));

        positionActions = new PositionActions(helper, this, TRADER, TRADER_PK);
        VM.makePersistent(address(positionActions));

        positionActions2 = new PositionActions(helper, this, TRADER2, TRADER2_PK);
        VM.makePersistent(address(positionActions2));

        _bounds[LINK] = ERC20Bounds({ min: 15e18, max: type(uint96).max, dust: 0.000001e18 });
        _bounds[DAI] = ERC20Bounds({ min: 100e18, max: type(uint96).max, dust: 0.0001e18 });
        _bounds[SDAI] = ERC20Bounds({ min: 100e18, max: type(uint96).max, dust: 0.0001e18 });
        _bounds[USDC] = ERC20Bounds({ min: 100e6, max: type(uint96).max / 1e12, dust: 0.0001e6 });
        _bounds[WETH] = ERC20Bounds({ min: 0.1e18, max: type(uint96).max, dust: 0.0000001e18 });
    }

    function init() public virtual;

    function init(uint256 /* blockNumber */ ) public virtual {
        nativeToken = IWETH9(address(token(WETH)));
    }

    function cleanTreasury() public {
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

        if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_AAVE)) {
            tmp.push(erc20(LINK));
            tmp.push(erc20(DAI));
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else if (MoneyMarketId.unwrap(mm) == MoneyMarketId.unwrap(MM_EXACTLY)) {
            tmp.push(erc20(USDC));
            tmp.push(erc20(WETH));
        } else {
            revert("Unsupported money market");
        }

        return tmp;
    }

    function createInstrument(ERC20Data memory baseData, ERC20Data memory quoteData) public returns (TestInstrument memory instrument) {
        Symbol symbol = Symbol.wrap(bytes16(abi.encodePacked(baseData.token.symbol(), quoteData.token.symbol())));
        VM.startPrank(TIMELOCK_ADDRESS);
        contango.createInstrument({ symbol: symbol, base: baseData.token, quote: quoteData.token });
        vault.setTokenSupport(baseData.token, true);
        vault.setTokenSupport(quoteData.token, true);
        VM.stopPrank();

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
        helper.assertNoBalances(instrument.base, address(contango), contangoBaseTolerance, "contango balance: base");
        helper.assertNoBalances(instrument.quote, address(contango), bounds(instrument.quoteData.symbol).dust, "contango balance: quote");
        helper.assertNoBalances(
            instrument.base, address(positionFactory.moneyMarket(positionId)), bounds(instrument.baseData.symbol).dust, "MM balance: base"
        );
        helper.assertNoBalances(
            instrument.quote,
            address(positionFactory.moneyMarket(positionId)),
            bounds(instrument.quoteData.symbol).dust,
            "MM balance: quote"
        );
        if (address(flp) != address(0)) {
            helper.assertNoBalances(
                instrument.base,
                address(flp),
                bounds(instrument.baseData.symbol).dust,
                string.concat("FLP (", VM.toString(address(flp)), ") balance: base")
            );
            helper.assertNoBalances(
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

    function etchNoFeeModel() public returns (address feeModelAddress, bytes memory previousBytecode) {
        feeModelAddress = address(contango.feeManager().feeModel());
        previousBytecode = feeModelAddress.code;
        VM.etch(feeModelAddress, address(noFeeModel).code);
    }

}

contract ArbitrumEnv is Env {

    constructor() {
        _moneyMarkets.push(MM_AAVE);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x86E53CF1B870786351Da77A57575e79CB55812CB),
            hasPermit: true
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            hasPermit: true
        });
        _erc20s[USDT] = ERC20Data({
            symbol: USDT,
            token: IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7),
            hasPermit: true
        });
        _erc20s[ARB] = ERC20Data({
            symbol: ARB,
            token: IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6),
            hasPermit: true
        });
        _erc20s[LUSD] = ERC20Data({
            symbol: LUSD,
            token: IERC20(0x93b346b6BC2548dA6A1E7d98E9a421B42541425b),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x0411D28c94d85A36bC72Cb0f875dfA8371D8fFfF),
            hasPermit: true
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
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
        orderManager = deployment.orderManager;
        oracle = deployment.oracle;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(aaveAddressProvider.getPoolDataProvider()));
    }

}

contract OptimismEnv is Env {

    constructor() {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_EXACTLY);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xCc232dcFAAE6354cE191Bd574108c1aD03f86450),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6),
            hasPermit: true
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3),
            hasPermit: false
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x4200000000000000000000000000000000000006),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        auditor = IAuditor(0xaEb62e6F27BC103702E7BC879AE98bceA56f027E);
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
        orderManager = deployment.orderManager;
        oracle = deployment.oracle;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(aaveAddressProvider.getPoolDataProvider()));
    }

}

contract PolygonEnv is Env {

    constructor() {
        _moneyMarkets.push(MM_AAVE);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0xb0897686c545045aFc77CF20eC7A532E3120E0F1),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xd9FFdb71EbE7496cC440152d43986Aae0AB76665),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xF9680D99D6C9589e2a93a78A04A279e509205945),
            hasPermit: false
        });
        _erc20s[WMATIC] = ERC20Data({
            symbol: WMATIC,
            token: IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb);
        aaveRewardsController = IAaveRewardsController(0x929EC64c34a17401F460460D4B9390518E5B473e);
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
        orderManager = deployment.orderManager;
        oracle = deployment.oracle;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(aaveAddressProvider.getPoolDataProvider()));
    }

}

contract MainnetEnv is Env {

    constructor() {
        _moneyMarkets.push(MM_AAVE);
        _moneyMarkets.push(MM_COMPOUND);

        _erc20s[LINK] = ERC20Data({
            symbol: LINK,
            token: IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c),
            hasPermit: false
        });
        _erc20s[DAI] = ERC20Data({
            symbol: DAI,
            token: IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9),
            hasPermit: false
        });
        _erc20s[SDAI] = ERC20Data({
            symbol: SDAI,
            token: IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xb9E6DBFa4De19CCed908BcbFe1d015190678AB5f),
            hasPermit: false
        });
        _erc20s[USDC] = ERC20Data({
            symbol: USDC,
            token: IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6),
            hasPermit: true
        });
        _erc20s[WETH] = ERC20Data({
            symbol: WETH,
            token: IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
            hasPermit: false
        });
        _erc20s[WBTC] = ERC20Data({
            symbol: WBTC,
            token: IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599),
            chainlinkUsdOracle: AggregatorV2V3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c), // BTC / USD
            hasPermit: false
        });
        _erc20s[RETH] = ERC20Data({
            symbol: RETH,
            token: IERC20(0xae78736Cd615f374D3085123A210448E74Fc6393),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x05225Cd708bCa9253789C1374e4337a019e99D56),
            hasPermit: false
        });
        _erc20s[GNO] = ERC20Data({
            symbol: GNO,
            token: IERC20(0x6810e776880C02933D47DB1b9fc05908e5386b96),
            chainlinkUsdOracle: AggregatorV2V3Interface(0x4A7Ad931cb40b564A1C453545059131B126BC828),
            hasPermit: false
        });

        spotStub = new SpotStub(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        VM.makePersistent(address(spotStub));

        uniswap = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        uniswapRouter = SwapRouter02(uniswap);
        balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        aaveAddressProvider = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
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
        orderManager = deployment.orderManager;
        oracle = deployment.oracle;
        feeManager = deployment.feeManager;
        tsQuoter = deployment.tsQuoter;
        positionFactory = contango.positionFactory();
        encoder = new Encoder(contango, IPoolDataProvider(aaveAddressProvider.getPoolDataProvider()));
    }

}

function fork(string memory name, uint256 blockNumber) {
    if (blockNumber > 0) VM.createSelectFork(name, blockNumber);
    else VM.createSelectFork(name);
}

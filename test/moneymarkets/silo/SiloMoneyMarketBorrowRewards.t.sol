//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

import "src/strategies/StrategyBuilder.sol";

contract SiloMoneyMarketBorrowRewardsTest is Test, Addresses {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Contango internal contango;
    ContangoLens internal lens;

    address internal rewardsToken;

    PositionId internal positionId = PositionId.wrap(0x775553442b555344430000000000000010ffffffff0100000000000000000000);

    address internal trader;

    function setUp() public {
        vm.createSelectFork("arbitrum", 245_238_456);

        trader = makeAddr("trader");

        rewardsToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;

        contango = Contango(proxyAddress("ContangoProxy"));
        lens = ContangoLens(proxyAddress("ContangoLensProxy"));

        ISiloLens siloLens = ISiloLens(_loadAddress("SiloLens"));
        ISiloIncentivesController incentivesController = ISiloIncentivesController(_loadAddress("SiloIncentivesController"));
        ISilo wstEthSilo = ISilo(_loadAddress("Silo_WSTETH_ETH"));
        IWETH9 weth = IWETH9(_loadAddress("NativeToken"));
        IERC20 stablecoin = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

        SiloMoneyMarket mm = new SiloMoneyMarket(contango, siloLens, incentivesController, wstEthSilo, weth, stablecoin);
        SiloMoneyMarketView mmv = new SiloMoneyMarketView(
            contango,
            weth,
            IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            siloLens,
            incentivesController,
            wstEthSilo,
            stablecoin
        );

        vm.startPrank(TIMELOCK_ADDRESS);
        lens.setMoneyMarketView(mmv);

        IMoneyMarket existentMoneyMarket = contango.positionFactory().moneyMarket(mm.moneyMarketId());
        UpgradeableBeacon beacon = ImmutableBeaconProxy(payable(address(existentMoneyMarket))).__beacon();
        beacon.upgradeTo(address(mm));

        vm.stopPrank();
    }

    StepCall[] internal steps;

    function testBorrowRewards() public {
        StrategyBuilder db = new StrategyBuilder(
            TIMELOCK,
            IMaestro(_loadAddress("MaestroProxy")),
            IERC721Permit2(_loadAddress("IERC721Permit2")),
            ContangoLens(_loadAddress("ContangoLensProxy"))
        );
        IERC20 base = IERC20(0xB86fb1047A955C0186c77ff6263819b37B32440D);

        deal(address(base), _loadAddress("VaultProxy"), 11_000e6);

        steps.push(StepCall(Step.VaultDeposit, abi.encode(base, 10_000e6)));
        steps.push(StepCall(Step.PositionDeposit, abi.encode(positionId, POSITION_ONE, 10_000e6)));
        steps.push(StepCall(Step.PositionBorrow, abi.encode(0, POSITION_ONE, 5000e6)));

        vm.prank(trader);
        StepResult[] memory results = db.process(steps);

        positionId = abi.decode(results[1].data, (PositionId));

        skip(1 minutes);

        (Reward[] memory borrowing, Reward[] memory lending) = lens.rewards(positionId);

        assertEq(borrowing.length, 1, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(borrowing[0].token.token), rewardsToken, "Borrow reward[0] token");
        assertEq(borrowing[0].token.name, "Arbitrum", "Borrow reward[0] name");
        assertEq(borrowing[0].token.symbol, "ARB", "Borrow reward[0] symbol");
        assertEq(borrowing[0].token.decimals, 18, "Borrow reward[0] decimals");
        assertEq(borrowing[0].token.unit, 1e18, "Borrow reward[0] unit");
        assertEqDecimal(borrowing[0].rate, 0.026485916603202788e18, borrowing[0].token.decimals, "Borrow reward[0] rate");
        assertEqDecimal(borrowing[0].claimable, 0.000463346842427845e18, borrowing[0].token.decimals, "Borrow reward[0] claimable");
        assertEqDecimal(borrowing[0].usdPrice, 0.536679969999997732e18, 18, "Borrow reward[0] usdPrice");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Arbitrum", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "ARB", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.010734328629532366e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0.000437891915250127e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.536679969999997732e18, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(trader);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient),
            lending[0].claimable + borrowing[0].claimable,
            IERC20(rewardsToken).decimals(),
            "Claimed ARB rewards"
        );
    }

    function testMetaData_Silo() public {
        lens.metaData(positionId);
    }

}

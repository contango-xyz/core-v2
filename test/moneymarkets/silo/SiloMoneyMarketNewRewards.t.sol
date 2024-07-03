//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract SiloMoneyMarketNewRewardsTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Contango internal contango;
    ContangoLens internal lens;

    address internal oldRewardsToken;
    address internal newRewardsToken;

    PositionId internal positionId = PositionId.wrap(0x5745544855534443000000000000000010ffffffff00000000000000000009c8);

    function setUp() public {
        // vm.createSelectFork("arbitrum", 195_400_019);
        vm.createSelectFork("arbitrum", 195_460_019);

        oldRewardsToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        newRewardsToken = 0x0341C0C0ec423328621788d4854119B97f44E391;

        contango = Contango(proxyAddress("ContangoProxy"));
        lens = ContangoLens(proxyAddress("ContangoLensProxy"));

        ISiloLens siloLens = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
        ISiloIncentivesController incentivesController = ISiloIncentivesController(0x7e5BFBb25b33f335e34fa0d78b878092931F8D20);
        ISilo wstEthSilo = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
        IWETH9 weth = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        IERC20 stablecoin = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        IERC20 arb = IERC20(0x912CE59144191C1204E64559FE8253a0e49E6548);

        SiloMoneyMarket mm = new SiloMoneyMarket(contango, siloLens, incentivesController, wstEthSilo, weth, stablecoin, arb);
        SiloMoneyMarketView mmv = new SiloMoneyMarketView(
            contango,
            weth,
            IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
            siloLens,
            incentivesController,
            wstEthSilo,
            stablecoin,
            arb
        );

        vm.startPrank(TIMELOCK_ADDRESS);
        lens.setMoneyMarketView(mmv);

        IMoneyMarket existentMoneyMarket = contango.positionFactory().moneyMarket(mm.moneyMarketId());
        UpgradeableBeacon beacon = ImmutableBeaconProxy(payable(address(existentMoneyMarket))).__beacon();
        beacon.upgradeTo(address(mm));

        vm.stopPrank();
    }

    function testRewardsArbAirdropped() public {
        // Simulate an airdrop of 10 ARB
        deal(oldRewardsToken, address(contango.positionFactory().moneyMarket(positionId)), 10e18);

        (Reward[] memory borrowing, Reward[] memory lending) = lens.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");

        assertEq(address(lending[0].token.token), newRewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Silo Governance Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "Silo", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.028765752421430123e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 0.000813523758268742e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.11129203806740038e18, 18, "Lend reward[0] usdPrice");

        assertEq(address(lending[1].token.token), oldRewardsToken, "Lend reward[1] token");
        assertEq(lending[1].token.name, "Arbitrum", "Lend reward[1] name");
        assertEq(lending[1].token.symbol, "ARB", "Lend reward[1] symbol");
        assertEq(lending[1].token.decimals, 18, "Lend reward[1] decimals");
        assertEq(lending[1].token.unit, 1e18, "Lend reward[1] unit");
        assertEqDecimal(lending[1].rate, 0, lending[1].token.decimals, "Lend reward[1] rate");
        assertEqDecimal(lending[1].claimable, 10e18, lending[1].token.decimals, "Lend reward[1] claimable");
        assertEqDecimal(lending[1].usdPrice, 1.655320119999998052e18, 18, "Lend reward[1] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(0xa5341a1f9C0aa8Aca9F94e1905459E6a965AfB4d);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(newRewardsToken).balanceOf(recipient), lending[0].claimable, IERC20(newRewardsToken).decimals(), "Claimed Silo rewards"
        );
        assertEqDecimal(
            IERC20(oldRewardsToken).balanceOf(recipient), lending[1].claimable, IERC20(oldRewardsToken).decimals(), "Claimed ARB rewards"
        );
    }

    function testMetaData_Silo() public {
        lens.metaData(positionId);
    }

}

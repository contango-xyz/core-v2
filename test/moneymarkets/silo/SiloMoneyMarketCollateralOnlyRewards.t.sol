//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract SiloMoneyMarketCollateralOnlyRewardsTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Contango internal contango;
    ContangoLens internal lens;

    address internal rewardsToken;

    PositionId internal positionId = PositionId.wrap(0x5054657a45544849323457455448000010ffffffff0100000000000000001306);

    function setUp() public {
        vm.createSelectFork("arbitrum", 220_838_575);

        rewardsToken = 0x0341C0C0ec423328621788d4854119B97f44E391;

        contango = Contango(proxyAddress("ContangoProxy"));
        lens = ContangoLens(proxyAddress("ContangoLensProxy"));

        ISiloLens siloLens = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
        ISiloIncentivesController incentivesController = ISiloIncentivesController(0x7e5BFBb25b33f335e34fa0d78b878092931F8D20);
        ISilo wstEthSilo = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
        IWETH9 weth = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
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

    function testCollateralOnlyRewards() public {
        (Reward[] memory borrowing, Reward[] memory lending) = lens.rewards(positionId);

        assertEq(borrowing.length, 0, "Borrow rewards length");
        assertEq(lending.length, 1, "Lend rewards length");

        assertEq(address(lending[0].token.token), rewardsToken, "Lend reward[0] token");
        assertEq(lending[0].token.name, "Silo Governance Token", "Lend reward[0] name");
        assertEq(lending[0].token.symbol, "Silo", "Lend reward[0] symbol");
        assertEq(lending[0].token.decimals, 18, "Lend reward[0] decimals");
        assertEq(lending[0].token.unit, 1e18, "Lend reward[0] unit");
        assertEqDecimal(lending[0].rate, 0.056759514394513759e18, lending[0].token.decimals, "Lend reward[0] rate");
        assertEqDecimal(lending[0].claimable, 368.637476407468698649e18, lending[0].token.decimals, "Lend reward[0] claimable");
        assertEqDecimal(lending[0].usdPrice, 0.051880293678938442e18, 18, "Lend reward[0] usdPrice");

        address recipient = makeAddr("bank");
        vm.prank(0xa521E425f37aCC731651565B41Ce3E5022274F4F);
        contango.claimRewards(positionId, recipient);
        assertEqDecimal(
            IERC20(rewardsToken).balanceOf(recipient), lending[0].claimable, IERC20(rewardsToken).decimals(), "Claimed Silo rewards"
        );
    }

    function testMetaData_Silo() public {
        lens.metaData(positionId);
    }

}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";

import "./dependencies/ILaunchpad.sol";
import "./dependencies/IVotingEscrow.sol";
import "./dependencies/IRewardDistributor.sol";
import "./dependencies/IRewardFaucet.sol";

import { ERC20Mock } from "../stub/ERC20Mock.sol";

contract VeTangoTest is BaseTest, Addresses {

    Env internal env;
    ILaunchpad internal launchpad = ILaunchpad(0x665a23707e9cFCe7bf07C52D375f5274ceDd6eB4);
    IVotingEscrow internal veTANGO;
    IRewardDistributor internal rewardDistributor;
    IRewardFaucet internal rewardFaucet;

    ERC20Mock internal TANGO_LP;
    ERC20Mock internal REWARD_TOKEN;

    address internal LP1;
    address internal LP2;
    address internal LP3;
    address internal keeper;
    address internal owner;

    uint256 rewardDistributorStartTime = 1_720_051_200; // Thursday, 4 July 2024 00:00:00

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(228_097_806); // Jul-02-2024 08:34:12 PM +UTC

        TANGO_LP = new ERC20Mock();
        REWARD_TOKEN = new ERC20Mock();
        LP1 = makeAddr("LP1");
        LP2 = makeAddr("LP2");
        LP3 = makeAddr("LP3");
        keeper = makeAddr("keeper");
        owner = makeAddr("owner");

        // vm.prank(owner);
        (veTANGO, rewardDistributor, rewardFaucet) = launchpad.deploy(
            address(TANGO_LP),
            "TANGO Voting Escrow",
            "veTANGO80-WETH20",
            365 days,
            rewardDistributorStartTime,
            address(0),
            address(0),
            address(0)
        );

        address smartWalletChecker = makeAddr("SmartWalletChecker");
        veTANGO.commit_smart_wallet_checker(smartWalletChecker);
        veTANGO.apply_smart_wallet_checker();
        vm.mockCall(smartWalletChecker, abi.encodeWithSelector(SmartWalletChecker.check.selector), abi.encode(true));

        rewardDistributor.addAllowedRewardTokens(toArray(REWARD_TOKEN));
    }

    function testLockedBalances_OneYear() public {
        _createLock(LP1, 10e18, 52 weeks);

        assertEqDecimal(veTANGO.balanceOf(LP1), 9.812134703176361676e18, 18, "Balance at creation");
        skip(4 weeks);
        assertEqDecimal(veTANGO.balanceOf(LP1), 9.045011415506691276e18, 18, "Balance after 4 weeks");
        skip(22 weeks); // 4 + 22 = 26
        assertEqDecimal(veTANGO.balanceOf(LP1), 4.825833333323504076e18, 18, "Balance after 6 months");
        skip(13 weeks); // 26 + 13 = 39
        assertEqDecimal(veTANGO.balanceOf(LP1), 2.332682648397075276e18, 18, "Balance after 9 months");
        skip(13 weeks); // 39 + 13 = 52
        assertEqDecimal(veTANGO.balanceOf(LP1), 0, 18, "Balance after 1 year");
    }

    function testLockedBalances_HalfYear() public {
        _createLock(LP1, 10e18, 26 weeks);

        assertEqDecimal(veTANGO.balanceOf(LP1), 4.825833333323504076e18, 18, "Balance at creation");
        skip(13 weeks);
        assertEqDecimal(veTANGO.balanceOf(LP1), 2.332682648397075276e18, 18, "Balance after 3 months");
        skip(13 weeks); // 13 + 13 = 26
        assertEqDecimal(veTANGO.balanceOf(LP1), 0, 18, "Balance after 6 months");
    }

    function testRewardsDistribution_AllSameLock_DiffAmounts() public {
        _createLock(LP1, 20e18, 365 days);
        _createLock(LP2, 30e18, 365 days);
        _createLock(LP3, 50e18, 365 days);

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        assertEqDecimal(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime), 10e18, 18, "Total rewards for the week"
        );

        // Rewards deposited on week N are claimable on week N+1
        skip(1 weeks);

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 2e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 3e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 5e18, 0.1e18, 18, "LP3 rewards");
    }

    function testRewardsDistribution_DiffLocks_SameAmount() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);
        _createLock(LP3, 10e18, 4 weeks);

        assertEqDecimal(veTANGO.balanceOf(LP1), 9.812134703176361676e18, 18, "LP1 balance");
        assertEqDecimal(veTANGO.balanceOf(LP2), 4.825833333323504076e18, 18, "LP2 balance");
        assertEqDecimal(veTANGO.balanceOf(LP3), 0.606655251140316876e18, 18, "LP3 balance");
        assertEqDecimal(veTANGO.totalSupply(), 15.244623287640182628e18, 18, "Total supply");

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        assertEqDecimal(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime), 10e18, 18, "Total rewards for the week"
        );

        // Rewards deposited on week N are claimable on week N+1
        skip(1 weeks + 1 days);

        // LP1: 9.812134703176361676e18 * 10e18 / 15.244623287640182628e18 = 6.45e18
        // LP2: 4.825833333323504076e18 * 10e18 / 15.244623287640182628e18 = 3.16e18
        // LP3: 0.606655251140316876e18 * 10e18 / 15.244623287640182628e18 = 0.39e18
        // 6.45 + 3.16 + 0.39 = 10

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 6.45e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 3.16e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.39e18, 0.1e18, 18, "LP3 rewards");
    }

    function testRewardsDistribution_AllSameLock_DiffAmounts_MultipleWeeks() public {
        _createLock(LP1, 20e18, 365 days);
        _createLock(LP2, 30e18, 365 days);
        _createLock(LP3, 50e18, 365 days);

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardFaucet), 10e18);
        rewardFaucet.depositEqualWeeksPeriod(REWARD_TOKEN, 10e18, 3);
        vm.stopPrank();

        assertApproxEqAbsDecimal(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime),
            3.33e18,
            0.1e18,
            18,
            "Total rewards for the week 1"
        );
        assertEq(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime + 1 weeks),
            0,
            "Total rewards for the week 2"
        );
        assertEq(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime + 2 weeks),
            0,
            "Total rewards for the week 3"
        );

        // Rewards deposited on week N are claimable on week N+1
        skip(1 weeks);

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 0.66e18, 0.1e18, 18, "LP1 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1e18, 0.1e18, 18, "LP2 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 1.66e18, 0.1e18, 18, "LP3 rewards week 1");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP1), 0.66e18, 0.1e18, 18, "LP1 rewards week 1");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP2), 1e18, 0.1e18, 18, "LP2 rewards week 1");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP3), 1.66e18, 0.1e18, 18, "LP3 rewards week 1");

        skip(1 weeks);

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 0.66e18, 0.1e18, 18, "LP1 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1e18, 0.1e18, 18, "LP2 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 1.66e18, 0.1e18, 18, "LP3 rewards week 2");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP1), 1.32e18, 0.1e18, 18, "LP1 rewards week 2");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP2), 2e18, 0.1e18, 18, "LP2 rewards week 2");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP3), 3.32e18, 0.1e18, 18, "LP3 rewards week 2");

        skip(1 weeks);

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 0.66e18, 0.1e18, 18, "LP1 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1e18, 0.1e18, 18, "LP2 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 1.66e18, 0.1e18, 18, "LP3 rewards week 3");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP1), 2e18, 0.1e18, 18, "LP1 rewards week 3");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP2), 3e18, 0.1e18, 18, "LP2 rewards week 3");
        assertApproxEqAbsDecimal(REWARD_TOKEN.balanceOf(LP3), 5e18, 0.1e18, 18, "LP3 rewards week 3");
    }

    function testRewardsDistribution_DiffLocks_DiffAmounts_MultipleWeeks() public {
        _createLock(LP1, 10e18, 4 weeks);
        _createLock(LP2, 10e18, 3 weeks);
        _createLock(LP3, 10e18, 2 weeks);

        vm.warp(rewardDistributorStartTime + 1);

        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP1), 0.57e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP2), 0.38e18, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP3), 0.19e18, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veTANGO.totalSupply(), 1.14e18, 0.1e18, 18, "Total supply");

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardFaucet), 10e18);
        rewardFaucet.depositEqualWeeksPeriod(REWARD_TOKEN, 10e18, 3);
        vm.stopPrank();

        assertApproxEqAbsDecimal(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime),
            3.33e18,
            0.1e18,
            18,
            "Total rewards for the week 1"
        );
        assertEq(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime + 1 weeks),
            0,
            "Total rewards for the week 2"
        );
        assertEq(
            rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime + 2 weeks),
            0,
            "Total rewards for the week 3"
        );

        // Rewards deposited on week N are claimable on week N+1
        skip(1 weeks);

        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP1), 0.38e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP2), 0.19e18, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veTANGO.totalSupply(), 0.57e18, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 1.66e18, 0.1e18, 18, "LP1 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1.11e18, 0.1e18, 18, "LP2 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.55e18, 0.1e18, 18, "LP3 rewards week 1");

        skip(1 weeks);

        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP1), 0.19e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP2), 0, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veTANGO.totalSupply(), 0.19e18, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 2.22e18, 0.1e18, 18, "LP1 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1.11e18, 0.1e18, 18, "LP2 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0, 0.1e18, 18, "LP3 rewards week 2");

        skip(1 weeks);

        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP1), 0, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP2), 0, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veTANGO.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veTANGO.totalSupply(), 0, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 3.33e18, 0.1e18, 18, "LP1 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 0, 0.1e18, 18, "LP2 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0, 0.1e18, 18, "LP3 rewards week 3");
    }

    function _createLock(address addr, uint256 amount, uint256 duration) internal {
        TANGO_LP.mint(addr, amount);
        vm.startPrank(addr);
        TANGO_LP.approve(address(veTANGO), amount);
        veTANGO.create_lock(amount, block.timestamp + duration);
        vm.stopPrank();
    }

}

interface SmartWalletChecker {

    function check(address) external view returns (bool);

}

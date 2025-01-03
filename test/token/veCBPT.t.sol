//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";

import { IBalancerVault } from "../dependencies/Balancer.sol";
import "./dependencies/IVotingEscrow.sol";
import "./dependencies/IRewardDistributor.sol";
import "./dependencies/IRewardFaucet.sol";
import "src/token/SmartWalletChecker.sol";

import { ERC20Mock } from "../stub/ERC20Mock.sol";

contract VeCbptTest is BaseTest {

    IBalancerVault constant balancerVault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IVotingEscrow constant veCBPT = IVotingEscrow(0x96Aa72542cE42F99F93de51e2F24Cc2601c6221a);
    IRewardDistributor constant rewardDistributor = IRewardDistributor(0xB35B3004125E342D9A996E1B274fe85Cc22D46f2);
    IRewardFaucet constant rewardFaucet = IRewardFaucet(0x57aF8e6567AdAcee07aced7873d17BD0E4D90eCc);
    address constant owner = 0x4577b1417BDd10bF1BBFC8CF29180f592b0c3190;
    IERC20 constant CBPT = IERC20(0x1ed1e6FA76E3dD9eA68D1FD8c4b8626EA5648DfA);

    ERC20Mock internal REWARD_TOKEN;

    address internal LP1;
    address internal LP2;
    address internal LP3;
    address internal keeper;

    uint256 rewardDistributorStartTime = 1_732_147_200; // Thursday, 21 November 2024 00:00:00

    function setUp() public {
        vm.createSelectFork("arbitrum", 269_189_138); // Oct-30-2024 10:00:54
        skip(20 days); // Nov-19-2024 10:00:54 - tests were originally written for a mock locker that would start rewards distribution a couple days after

        REWARD_TOKEN = new ERC20Mock();
        LP1 = makeAddr("LP1");
        LP2 = makeAddr("LP2");
        LP3 = makeAddr("LP3");
        keeper = makeAddr("keeper");

        address smartWalletChecker = address(new SmartWalletChecker());

        vm.startPrank(owner);
        veCBPT.commit_smart_wallet_checker(smartWalletChecker);
        veCBPT.apply_smart_wallet_checker();
        rewardDistributor.addAllowedRewardTokens(toArray(REWARD_TOKEN));
        vm.stopPrank();
    }

    function testLockedBalances_OneYear() public {
        _createLock(LP1, 10e18, 52 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "Balance at creation");
        skip(4 weeks);
        assertEqDecimal(veCBPT.balanceOf(LP1), 9.057060502264657602e18, 18, "Balance after 4 weeks");
        skip(22 weeks); // 4 + 22 = 26
        assertEqDecimal(veCBPT.balanceOf(LP1), 4.837882420081470402e18, 18, "Balance after 6 months");
        skip(13 weeks); // 26 + 13 = 39
        assertEqDecimal(veCBPT.balanceOf(LP1), 2.344731735155041602e18, 18, "Balance after 9 months");
        skip(13 weeks); // 39 + 13 = 52
        assertEqDecimal(veCBPT.balanceOf(LP1), 0, 18, "Balance after 1 year");
    }

    function testLockedBalances_HalfYear() public {
        _createLock(LP1, 10e18, 26 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 4.837882420081470402e18, 18, "Balance at creation");
        skip(13 weeks);
        assertEqDecimal(veCBPT.balanceOf(LP1), 2.344731735155041602e18, 18, "Balance after 3 months");
        skip(13 weeks); // 13 + 13 = 26
        assertEqDecimal(veCBPT.balanceOf(LP1), 0, 18, "Balance after 6 months");
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

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 4.837882420081470402e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.618704337898283202e18, 18, "LP3 balance");
        assertEqDecimal(veCBPT.totalSupply(), 15.280770547914081606e18, 18, "Total supply");

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        uint256 distributedTokens = rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime);
        assertEqDecimal(distributedTokens, 10e18, 18, "Total rewards for the week");

        // LP1: 9.824183789934328002e18 * 10e18 / 15.280770547914081606e18 = 6.45e18
        uint256 expectedLP1Balance = 6.45e18;

        // Gotta checkpoint the user and totalSupply to get the correct balance
        rewardDistributor.checkpointUser(LP1);
        rewardDistributor.checkpoint();

        assertApproxEqAbsDecimal(
            rewardDistributor.getUserBalanceAtTimestamp(LP1, rewardDistributorStartTime) * distributedTokens
                / rewardDistributor.getTotalSupplyAtTimestamp(rewardDistributorStartTime),
            expectedLP1Balance,
            0.1e18,
            18,
            "LP1 balance"
        );

        // Rewards deposited on week N are claimable on week N+1
        skip(1 weeks + 1 days);

        // LP2: 4.837882420081470402e18 * 10e18 / 15.280770547914081606e18 = 3.16e18
        // LP3: 0.618704337898283202e18 * 10e18 / 15.280770547914081606e18 = 0.39e18
        // 6.45 + 3.16 + 0.39 = 10

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), expectedLP1Balance, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 3.16e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.39e18, 0.1e18, 18, "LP3 rewards");
    }

    function testRewardsDistribution_DiffLocks_SameAmount_ClaimAfterExpiry() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);
        _createLock(LP3, 10e18, 4 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 4.837882420081470402e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.618704337898283202e18, 18, "LP3 balance");
        assertEqDecimal(veCBPT.totalSupply(), 15.280770547914081606e18, 18, "Total supply");

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        uint256 distributedTokens = rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime);
        assertEqDecimal(distributedTokens, 10e18, 18, "Total rewards for the week");

        // LP3 stake is already expired
        skip(6 weeks + 1 days);

        assertEqDecimal(veCBPT.balanceOf(LP3), 0, 18, "LP3 balance");

        // LP1: 9.824183789934328002e18 * 10e18 / 15.280770547914081606e18 = 6.45e18
        // LP2: 4.837882420081470402e18 * 10e18 / 15.280770547914081606e18 = 3.16e18
        // LP3: 0.618704337898283202e18 * 10e18 / 15.280770547914081606e18 = 0.39e18
        // 6.45 + 3.16 + 0.39 = 10

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 6.45e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 3.16e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.39e18, 0.1e18, 18, "LP3 rewards");
    }

    function testRewardsDistribution_DiffLocks_SameAmount_ClaimAfterExpiry_AndUnstake() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);
        _createLock(LP3, 10e18, 4 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 4.837882420081470402e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.618704337898283202e18, 18, "LP3 balance");
        assertEqDecimal(veCBPT.totalSupply(), 15.280770547914081606e18, 18, "Total supply");

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        uint256 distributedTokens = rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime);
        assertEqDecimal(distributedTokens, 10e18, 18, "Total rewards for the week");

        // LP3 stake is already expired
        skip(6 weeks + 1 days);
        vm.prank(LP3);
        veCBPT.withdraw();
        assertEqDecimal(veCBPT.balanceOf(LP3), 0, 18, "LP3 balance");

        // LP1: 9.824183789934328002e18 * 10e18 / 15.280770547914081606e18 = 6.45e18
        // LP2: 4.837882420081470402e18 * 10e18 / 15.280770547914081606e18 = 3.16e18
        // LP3: 0.618704337898283202e18 * 10e18 / 15.280770547914081606e18 = 0.39e18
        // 6.45 + 3.16 + 0.39 = 10

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 6.45e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 3.16e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.39e18, 0.1e18, 18, "LP3 rewards");
    }

    function testStakeWithoutUnstaking() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);
        _createLock(LP3, 10e18, 4 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 4.837882420081470402e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.618704337898283202e18, 18, "LP3 balance");

        // LP3 stake is already expired
        skip(6 weeks + 1 days);
        assertEqDecimal(veCBPT.balanceOf(LP3), 0, 18, "LP3 balance");

        vm.prank(LP3);
        vm.expectRevert("Withdraw old tokens first");
        veCBPT.create_lock(1e18, block.timestamp + 10 weeks);
    }

    function testRewardsDistribution_DiffLocks_SameAmount_ClaimAfterExpiry_AndRestake() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);
        _createLock(LP3, 10e18, 4 weeks);

        assertEqDecimal(veCBPT.balanceOf(LP1), 9.824183789934328002e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 4.837882420081470402e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.618704337898283202e18, 18, "LP3 balance");
        assertEqDecimal(veCBPT.totalSupply(), 15.280770547914081606e18, 18, "Total supply");

        vm.warp(rewardDistributorStartTime + 1);

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        uint256 distributedTokens = rewardDistributor.getTokensDistributedInWeek(REWARD_TOKEN, rewardDistributorStartTime);
        assertEqDecimal(distributedTokens, 10e18, 18, "Total rewards for the week");

        // LP3 stake is already expired
        skip(6 weeks + 1 days);
        vm.prank(LP3);
        veCBPT.withdraw();

        _createLock(LP3, 10e18, 4 weeks);

        skip(1 weeks + 1 days);

        assertEqDecimal(veCBPT.balanceOf(LP1), 8.383561326720620963e18, 18, "LP1 balance");
        assertEqDecimal(veCBPT.balanceOf(LP2), 3.397259956867763363e18, 18, "LP2 balance");
        assertEqDecimal(veCBPT.balanceOf(LP3), 0.520547628106499363e18, 18, "LP3 balance");

        REWARD_TOKEN.mint(keeper, 10e18);
        vm.startPrank(keeper);
        REWARD_TOKEN.approve(address(rewardDistributor), 10e18);
        rewardDistributor.depositToken(REWARD_TOKEN, 10e18);
        vm.stopPrank();

        skip(1 weeks + 1 days);

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 13.224926971762414799e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 5.933787731256085685e18, 0.1e18, 18, "LP2 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.841285296981499512e18, 0.1e18, 18, "LP3 rewards");
    }

    function testRewardsDistribution_LockIncreases() public {
        _createLock(LP1, 10e18, 52 weeks);
        _createLock(LP2, 10e18, 26 weeks);

        vm.warp(rewardDistributorStartTime - 1);
        _extendLock(LP2, 26 weeks);

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

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 5e18, 0.1e18, 18, "LP1 rewards");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 5e18, 0.1e18, 18, "LP2 rewards");
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

        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP1), 0.57e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP2), 0.38e18, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP3), 0.19e18, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veCBPT.totalSupply(), 1.14e18, 0.1e18, 18, "Total supply");

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

        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP1), 0.38e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP2), 0.19e18, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veCBPT.totalSupply(), 0.57e18, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 1.66e18, 0.1e18, 18, "LP1 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1.11e18, 0.1e18, 18, "LP2 rewards week 1");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0.55e18, 0.1e18, 18, "LP3 rewards week 1");

        skip(1 weeks);

        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP1), 0.19e18, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP2), 0, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veCBPT.totalSupply(), 0.19e18, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 2.22e18, 0.1e18, 18, "LP1 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 1.11e18, 0.1e18, 18, "LP2 rewards week 2");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0, 0.1e18, 18, "LP3 rewards week 2");

        skip(1 weeks);

        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP1), 0, 0.1e18, 18, "LP1 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP2), 0, 0.1e18, 18, "LP2 balance");
        assertApproxEqAbsDecimal(veCBPT.balanceOf(LP3), 0, 0.1e18, 18, "LP3 balance");
        assertApproxEqAbsDecimal(veCBPT.totalSupply(), 0, 0.1e18, 18, "Total supply");

        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP1, REWARD_TOKEN), 3.33e18, 0.1e18, 18, "LP1 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP2, REWARD_TOKEN), 0, 0.1e18, 18, "LP2 rewards week 3");
        assertApproxEqAbsDecimal(rewardDistributor.claimToken(LP3, REWARD_TOKEN), 0, 0.1e18, 18, "LP3 rewards week 3");
    }

    function _createLock(address addr, uint256 amount, uint256 duration) internal {
        deal(address(CBPT), addr, amount);
        vm.startPrank(addr);
        CBPT.approve(address(veCBPT), amount);
        veCBPT.create_lock(amount, block.timestamp + duration);
        vm.stopPrank();
    }

    function _increaseAmount(address addr, uint256 amount) internal {
        deal(address(CBPT), addr, amount);
        vm.startPrank(addr);
        CBPT.approve(address(veCBPT), amount);
        veCBPT.increase_amount(amount);
        vm.stopPrank();
    }

    function _extendLock(address addr, uint256 extension) internal {
        uint256 currEnd = veCBPT.locked__end(addr);
        vm.prank(addr);
        veCBPT.increase_unlock_time(currEnd + extension);
    }

}

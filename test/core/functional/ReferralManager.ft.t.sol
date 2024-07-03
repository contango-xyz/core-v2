//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../BaseTest.sol";
import "src/core/ReferralManager.sol";

contract ReferralManagerTest is BaseTest, IReferralManagerEvents {

    ReferralManager sut;

    address timelock = address(0x10c);
    address mod = address(0x0dd);
    address influencer = address(0x133c4);
    address trader = address(0xb0b);

    function setUp() public {
        sut = new ReferralManager(Timelock.wrap(payable(timelock)));
        vm.prank(timelock);
        sut.grantRole(MODIFIER_ROLE, mod);
    }

    function testRegisterReferralCode() public {
        vm.prank(influencer);
        sut.registerReferralCode("abc");
        assertEq(sut.referralCodes("abc"), influencer);
    }

    function testRegisterMultipleReferralCodes() public {
        vm.startPrank(influencer);
        sut.registerReferralCode("abc");
        sut.registerReferralCode("def");
        vm.stopPrank();
        assertEq(sut.referralCodes("abc"), influencer);
        assertEq(sut.referralCodes("def"), influencer);
    }

    function testIsCodeAvailable() public {
        assertEq(sut.isCodeAvailable("abc"), true);
        sut.registerReferralCode("abc");
        assertEq(sut.isCodeAvailable("abc"), false);
    }

    function testReferralCodeUnavailable() public {
        sut.registerReferralCode("abc");

        vm.startPrank(influencer);
        vm.expectRevert(abi.encodeWithSelector(IReferralManager.ReferralCodeUnavailable.selector, bytes32("abc")));
        sut.registerReferralCode("abc");
    }

    function testRegisterReferrer() public {
        vm.prank(influencer);
        sut.registerReferralCode("abc");
        vm.prank(trader);
        sut.setTraderReferralByCode("abc");
        assertEq(sut.referrals(trader), influencer);
    }

    function testCannotSelfRefer() public {
        vm.startPrank(influencer);
        sut.registerReferralCode("abc");
        vm.expectRevert(IReferralManager.CannotSelfRefer.selector);
        sut.setTraderReferralByCode("abc");
        vm.stopPrank();
    }

    function testCannotChangeReferralCode() public {
        // setup codes
        vm.startPrank(influencer);
        sut.registerReferralCode("old");
        sut.registerReferralCode("new");
        vm.stopPrank();

        vm.startPrank(trader);
        // register
        sut.setTraderReferralByCode("old");

        // try to change
        vm.expectRevert(abi.encodeWithSelector(IReferralManager.ReferralCodeAlreadySet.selector, bytes32("new")));
        sut.setTraderReferralByCode("new");
        vm.stopPrank();
    }

    function testTraderCannotSetAnUnregisteredReferralCode() public {
        vm.startPrank(trader);
        vm.expectRevert(abi.encodeWithSelector(IReferralManager.ReferralCodeNotRegistered.selector, bytes32("abc")));
        sut.setTraderReferralByCode("abc");
        vm.stopPrank();
    }

    function testCodeRegisteredEventEmitted() public {
        vm.prank(influencer);
        vm.expectEmit(true, true, true, true);
        emit ReferralCodeRegistered(influencer, bytes32("abc"));
        sut.registerReferralCode("abc");
    }

    function testTraderReferredEmitted() public {
        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        vm.expectEmit(true, true, true, true);
        emit TraderReferred(trader, influencer, bytes32("abc"));
        sut.setTraderReferralByCode("abc");
    }

    function testDefaultRewards() public view {
        assertEq(sut.referrerRewardPercentage(), 0);
        assertEq(sut.traderRebatePercentage(), 0);
    }

    function testSetInfluencerRewardPercentage() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.8e4, 0);
        assertEq(sut.referrerRewardPercentage(), 0.8e4);
    }

    function testSetTraderRewardPercentage() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0, 0.2e4);
        assertEq(sut.traderRebatePercentage(), 0.2e4);
    }

    function testRewardsCannotBeOver100Percent() public {
        vm.expectRevert(IReferralManager.RewardsConfigCannotExceedMax.selector);
        vm.prank(timelock);
        sut.setRewardsAndRebates(0, 1e4 + 1);
        vm.expectRevert(IReferralManager.RewardsConfigCannotExceedMax.selector);
        vm.prank(timelock);
        sut.setRewardsAndRebates(1e4 + 1, 0);
    }

    function testSumOfRewardsCannotBeOver100Percent() public {
        vm.expectRevert(IReferralManager.RewardsConfigCannotExceedMax.selector);
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.5e4 + 1, 0.5e4);

        vm.expectRevert(IReferralManager.RewardsConfigCannotExceedMax.selector);
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.5e4, 0.5e4 + 1);
    }

    function testRewardsGoToTheProtocolWhenNoReferrerIsSet() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.5e4, 0.5e4);

        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        FeeDistribution memory fees = sut.calculateRewardDistribution(trader, 100e4);
        assertEq(fees.protocol, 100e4);
        assertEq(fees.referrer, 0);
        assertEq(fees.trader, 0);
        assertEq(fees.referrerAddress, address(0));
    }

    function testRewardsAreDistributedToTheTraderAndInfluencerCorrectly() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.3e4, 0.6e4);

        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        sut.setTraderReferralByCode("abc");

        FeeDistribution memory fees = sut.calculateRewardDistribution(trader, 100e2);
        assertEq(fees.referrer, 30e2);
        assertEq(fees.trader, 60e2);
        assertEq(fees.protocol, 10e2);
        assertEq(fees.referrerAddress, influencer);
    }

    function testRewardsAreDistributedToTheTraderAndInfluencerCorrectlyWithoutRoundingErrors() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.6e4, 0.3e4);

        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        sut.setTraderReferralByCode("abc");

        uint256 amount = 99;

        FeeDistribution memory fees = sut.calculateRewardDistribution(trader, amount);
        assertEq(fees.referrer + fees.trader + fees.protocol, amount);
    }

    function testRewardsToTheTraderAndInfluencerAreRoundedDown() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.1e4, 0.1e4);

        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        sut.setTraderReferralByCode("abc");

        uint256 amount = 99;

        FeeDistribution memory fees = sut.calculateRewardDistribution(trader, amount);
        assertEq(fees.referrer, 9);
        assertEq(fees.trader, 9);
        assertEq(fees.protocol, 81);
        assertEq(fees.referrerAddress, influencer);
    }

    function testRewardsAndRebatesEmitsEvent() public {
        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit RewardsAndRebatesSet(0.1e4, 0.1e4);
        sut.setRewardsAndRebates(0.1e4, 0.1e4);
    }

    function testDistributionAlsoReturnsReferrerAddress() public {
        vm.prank(timelock);
        sut.setRewardsAndRebates(0.1e4, 0.1e4);

        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(trader);
        sut.setTraderReferralByCode("abc");

        uint256 amount = 99;

        FeeDistribution memory fees = sut.calculateRewardDistribution(trader, amount);
        assertEq(fees.referrerAddress, influencer);
    }

    function testShouldNotBeAbleToSetRebatesWithoutAdminRole() public {
        expectAccessControl(influencer, sut.DEFAULT_ADMIN_ROLE());
        sut.setRewardsAndRebates(0.1e4, 0.1e4);
    }

    function testShouldBeAbleToRegisterACodeForAnAddress() public {
        vm.prank(influencer);
        sut.registerReferralCode("abc");

        vm.prank(mod);
        sut.setTraderReferralByCodeForAddress("abc", trader);
    }

    function testShouldRevertWhenSettingByCodeForAddress() public {
        vm.prank(influencer);
        sut.registerReferralCode("abc");

        // cannot self refer
        vm.expectRevert();
        vm.prank(mod);
        sut.setTraderReferralByCodeForAddress("abc", influencer);

        // cannot use code that doesn't exists
        vm.expectRevert();
        vm.prank(mod);
        sut.setTraderReferralByCodeForAddress("abc!", trader);

        expectAccessControl(influencer, MODIFIER_ROLE);
        sut.setTraderReferralByCodeForAddress("abc", trader);
    }

}

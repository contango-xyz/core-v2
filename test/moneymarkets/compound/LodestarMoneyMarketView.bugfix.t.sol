//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract LodestarMoneyMarketViewBugfixTest is Test {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_RewardsOverflow() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x574554485553444300000000000000000cffffffff00000000000000000003ef);

        vm.createSelectFork("arbitrum", 182_342_009);
        (Reward[] memory borrowingBefore, Reward[] memory lendingBefore) = contangoLens.rewards(positionId);
        assertEq(borrowingBefore.length, 2, "borrowingBefore.length");
        assertEq(lendingBefore.length, 2, "lendingBefore.length");

        vm.createSelectFork("arbitrum", 182_342_010);

        // should fail with an underflow
        vm.expectRevert();
        contangoLens.rewards(positionId);

        // replace LodestarMoneyMarketView
        vm.etch(
            0x3BbEA51FBA7235621D5a89AC3B6D3e261E6117DE,
            address(
                new LodestarMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _reverseLookup: CompoundReverseLookup(0xB3863D03938eAD437E3f136778531DcB89F29EaD),
                    _rewardsTokenOracle: address(0x49bB23DfAe944059C2403BCc255c5a9c0F851a8D),
                    _nativeUsdOracle: IAggregatorV2V3(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612)
                })
            ).code
        );

        (Reward[] memory borrowingAfter, Reward[] memory lendingAfter) = contangoLens.rewards(positionId);
        assertEq(borrowingAfter.length, 1, "borrowingAfter.length");
        assertRewards(borrowingBefore[1], borrowingAfter[0], "borrowingAfter[0]");

        assertEq(lendingAfter.length, 1, "lendingAfter.length");
    }

    function assertRewards(Reward memory rewardBefore, Reward memory rewardAfter, string memory label) internal pure {
        assertEq(address(rewardAfter.token.token), address(rewardBefore.token.token), string.concat(label, ".token.token"));
        assertApproxEqRel(rewardAfter.rate, rewardBefore.rate, 0.00001e18, string.concat(label, ".rate"));
        assertEq(rewardAfter.claimable, rewardBefore.claimable, string.concat(label, ".claimable"));
    }

}

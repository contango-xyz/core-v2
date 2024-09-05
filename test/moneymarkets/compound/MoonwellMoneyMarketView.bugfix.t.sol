//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract MoonwellMoneyMarketViewBugfixTest is Test {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_RewardsOnNewWellToken() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x574554485553444300000000000000000dffffffff00000000000000000001bb);

        vm.createSelectFork("base", 13_412_068);

        // should fail
        vm.expectRevert();
        contangoLens.rewards(positionId);

        // replace MoonwellMoneyMarketView
        vm.etch(
            0x8D82f03d20ac0708c2BE2D606dd86B2bFE21D5F7,
            address(
                new MoonwellMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _reverseLookup: CompoundReverseLookup(0xD4A36f40657899e566F48B81339b49fA6eF50142),
                    _bridgedWellTokenOracle: 0xffA3F8737C39e36dec4300B162c2153c67c8352f,
                    _bridgedWell: IERC20(0xFF8adeC2221f9f4D8dfbAFa6B9a297d17603493D),
                    _nativeWellTokenOracle: 0x89D0F320ac73dd7d9513FFC5bc58D1161452a657,
                    _nativeWell: IERC20(0xA88594D404727625A9437C3f886C7643872296AE),
                    _nativeUsdOracle: IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70)
                })
            ).code
        );

        (Reward[] memory borrowing, Reward[] memory lending) = contangoLens.rewards(positionId);
        assertEq(borrowing.length, 3, "Borrow rewards length");
        assertEq(lending.length, 2, "Lend rewards length");
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../TestSetup.t.sol";

contract CometMoneyMarketViewBugfixTest is Test {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_RewardsOverflow() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x777374455448574554480000000000000effffffff0000000002000000000000);

        vm.createSelectFork("mainnet", 19_639_119);
        vm.expectRevert(IComet.BadAsset.selector);
        contangoLens.metaData(positionId);

        // replace CometMoneyMarketView
        vm.etch(
            0x0aeFf85B59FB641C2f60cdd396294446CB93e27F,
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                    _nativeUsdOracle: IAggregatorV2V3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
                    _reverseLookup: CometReverseLookup(0x94e46A68814D09a3131221eec190512a374e6BF1),
                    _cometRewards: ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40),
                    _compOracle: IAggregatorV2V3(0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5)
                })
            ).code
        );

        contangoLens.metaData(positionId);
    }

    function testBugFix_LiquidityOverflow() public {
        ContangoLens contangoLens = ContangoLens(0xe03835Dfae2644F37049c1feF13E8ceD6b1Bb72a);
        positionId = PositionId.wrap(0x574554485553446243000000000000000effffffff0000000001000000000000);

        vm.createSelectFork("base", 13_278_883);
        vm.expectRevert();
        contangoLens.metaData(positionId);

        // replace CometMoneyMarketView
        vm.etch(
            0x163046ca3A4179038e3A8c07915D0ACC7F5081Bc,
            address(
                new CometMoneyMarketView({
                    _contango: IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E),
                    _nativeToken: IWETH9(0x4200000000000000000000000000000000000006),
                    _nativeUsdOracle: IAggregatorV2V3(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                    _reverseLookup: CometReverseLookup(0xD915a274Dfc25535fe64bEAa9F1Ce032eb341945),
                    _cometRewards: ICometRewards(0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1),
                    _compOracle: IAggregatorV2V3(0x9DDa783DE64A9d1A60c49ca761EbE528C35BA428)
                })
            ).code
        );

        contangoLens.metaData(positionId);
    }

}

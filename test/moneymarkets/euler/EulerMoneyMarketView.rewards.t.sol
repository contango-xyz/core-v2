//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract EulerMoneyMarketViewRewardsTest is BaseTest, Addresses {

    using Address for *;
    using ERC20Lib for *;

    IEulerVault public constant woethVault = IEulerVault(0x01d1a1cd5955B2feFb167e8bc200A00BfAda8977);
    IEulerVault public constant wethVault = IEulerVault(0xe2D6A2a16ff6d3bbc4C90736A7e6F7Cc3C9B8fa9);
    IERC20 public constant ogn = IERC20(0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26);

    uint16 woethId;
    uint16 wethId;

    PositionId positionId;
    EulerMoneyMarketView mmv;
    EulerRewardsOperator rewardOperator;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_871_544);

        mmv = EulerMoneyMarketView(_loadAddress("EulerMoneyMarketView"));
        EulerReverseLookup reverseLookup = EulerReverseLookup(_loadAddress("EulerReverseLookup"));
        woethId = reverseLookup.vaultToId(woethVault);
        wethId = reverseLookup.vaultToId(wethVault);

        positionId = encode(Symbol.wrap("WOETHWETH"), MM_EULER, PERP, 0, baseQuotePayload(woethId, wethId));

        IContango contango = IContango(_loadAddress("ContangoProxy"));
        IWETH9 nativeToken = IWETH9(_loadAddress("NativeToken"));
        IAggregatorV2V3 nativeUsdOracle = IAggregatorV2V3(_loadAddress("ChainlinkNativeUsdOracle"));
        rewardOperator = EulerRewardsOperator(_loadAddress("EulerRewardsOperator"));
        IEulerVaultLens lens = IEulerVaultLens(_loadAddress("EulerVaultLens"));

        // replace EulerMoneyMarketView
        vm.etch(
            address(mmv),
            address(new EulerMoneyMarketView(contango, nativeToken, nativeUsdOracle, reverseLookup, rewardOperator, lens)).code
        );
    }

    function testRewardsData() public {
        EulerMoneyMarketView.RawData memory data = mmv.rawData(positionId);

        assertEq(data.rewardsData.length, 0);

        vm.prank(TIMELOCK_ADDRESS);
        rewardOperator.addLiveReward(woethVault, ogn);

        data = mmv.rawData(positionId);

        assertEq(data.rewardsData.length, 1);
    }

}

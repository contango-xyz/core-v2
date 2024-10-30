//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract EulerRewardsOperatorTest is BaseTest, Addresses {

    using Address for *;
    using ERC20Lib for *;

    IEulerVault private constant woethVault = IEulerVault(0x01d1a1cd5955B2feFb167e8bc200A00BfAda8977);
    IERC20 private constant OGN_TOKEN = IERC20(0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26);
    IERC20 private constant LINK_TOKEN = IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    IERC20 private constant DAI_TOKEN = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant SDAI_TOKEN = IERC20(0x83F20F44975D03b1b09e64809B757c47f942BEeA);
    IERC20 private constant USDC_TOKEN = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant WETH_TOKEN = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    EulerRewardsOperator rewardOperator;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_871_544);
        rewardOperator = EulerRewardsOperator(_loadAddress("EulerRewardsOperator"));
    }

    function testCanAddUpToFiveRewards() public {
        vm.startPrank(TIMELOCK_ADDRESS);
        rewardOperator.addLiveReward(woethVault, OGN_TOKEN); // 1
        rewardOperator.addLiveReward(woethVault, LINK_TOKEN); // 2
        rewardOperator.addLiveReward(woethVault, DAI_TOKEN); // 3
        rewardOperator.addLiveReward(woethVault, SDAI_TOKEN); // 4
        rewardOperator.addLiveReward(woethVault, USDC_TOKEN); // 5
        vm.expectRevert(EulerRewardsOperator.TooManyRewards.selector);
        rewardOperator.addLiveReward(woethVault, WETH_TOKEN); // 6
        vm.stopPrank();
    }

}

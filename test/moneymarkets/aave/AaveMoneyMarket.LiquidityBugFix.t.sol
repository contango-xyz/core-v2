//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract AaveMoneyMarketLiquidityBugFixTest is Test, Addresses {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    Contango internal contango;
    ContangoLens internal lens;
    IMoneyMarket internal sut;

    PositionId internal positionId = PositionId.wrap(0x7765455448574554480000000000000001ffffffff0100000000000000001364);
    IERC20 internal weETH = IERC20(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe);

    function setUp() public {
        vm.createSelectFork("arbitrum", 221_389_183);

        contango = Contango(proxyAddress("ContangoProxy"));
        lens = ContangoLens(proxyAddress("ContangoLensProxy"));

        sut = IMoneyMarket(0x302E420eC2fb4F99b651AA66D1C934B8D8bfF48D);

        IPoolAddressesProvider addressProvider = IPoolAddressesProvider(_loadAddress("AavePoolAddressesProvider"));
        IAaveRewardsController rewardsController = IAaveRewardsController(_loadAddressMaybe("AaveRewardsController"));
        IWETH9 nativeToken = IWETH9(_loadAddress("NativeToken"));
        IAggregatorV2V3 nativeUsdOracle = IAggregatorV2V3(_loadAddress("ChainlinkNativeUsdOracle"));

        AaveMoneyMarketView mmv = new AaveMoneyMarketView(
            MM_AAVE, "AaveV3", contango, addressProvider, rewardsController, nativeToken, nativeUsdOracle, AaveMoneyMarketView.Version.V32
        );

        vm.startPrank(TIMELOCK_ADDRESS);
        lens.setMoneyMarketView(mmv);

        vm.stopPrank();
    }

    function testLiquidity() public {
        // setup
        uint256 lendAmount = 0.664e18;

        (, uint256 lendingLiquidity) = lens.liquidity(positionId);
        assertEqDecimal(lendingLiquidity, 0, weETH.decimals(), "lending liquidity");

        // lend
        _dealAndApprove(weETH, address(contango), lendAmount, address(sut));
        vm.prank(address(contango));
        vm.expectRevert();
        sut.lend(positionId, weETH, lendAmount);
    }

    function _dealAndApprove(IERC20 _token, address to, uint256 amount, address approveTo) internal {
        deal(address(_token), to, amount);
        VM.prank(to);
        _token.approve(approveTo, amount);
    }

}

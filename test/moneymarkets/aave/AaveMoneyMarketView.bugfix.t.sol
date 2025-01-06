//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract AaveMoneyMarketViewBugFixTest is Test, Addresses {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_ThresholdExistingEmode() public {
        vm.createSelectFork("linea", 12_532_919);

        ContangoLens contangoLens = ContangoLens(_loadAddress("ContangoLensProxy"));
        positionId = PositionId.wrap(0x5553444355534454000000000000000012ffffffff0100000000000000000035);

        (uint256 ltv, uint256 liquidationThreshold) = contangoLens.thresholds(positionId);
        assertEq(ltv, 0.8e18, "ltv");
        assertEq(liquidationThreshold, 0.85e18, "liquidationThreshold");

        IMoneyMarketView moneyMarketView = new AaveMoneyMarketView({
            _moneyMarketId: MM_ZEROLEND,
            _moneyMarketName: "ZeroLend",
            _contango: IContango(_loadAddress("ContangoProxy")),
            _poolAddressesProvider: IPoolAddressesProvider(_loadAddress("ZeroLendPoolAddressesProvider")),
            _rewardsController: IAaveRewardsController(_loadAddressMaybe("ZeroLendRewardsController")),
            _nativeToken: IWETH9(_loadAddress("NativeToken")),
            _nativeUsdOracle: IAggregatorV2V3(_loadAddress("ChainlinkNativeUsdOracle")),
            _version: AaveMoneyMarketView.Version.V3
        });

        vm.prank(TIMELOCK_ADDRESS);
        contangoLens.setMoneyMarketView(moneyMarketView);

        (ltv, liquidationThreshold) = contangoLens.thresholds(positionId);
        assertEq(ltv, 0.97e18, "ltv");
        assertEq(liquidationThreshold, 0.975e18, "liquidationThreshold");
    }

}

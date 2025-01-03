//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../utils.t.sol";

contract SiloMoneyMarketViewBugFixTest is Test, Addresses {

    Env internal env;
    PositionId internal positionId;

    function testBugFix_IrmData() public {
        vm.createSelectFork("base", 22_350_366);

        ContangoLens contangoLens = ContangoLens(_loadAddress("ContangoLensProxy"));
        positionId = PositionId.wrap(0x6362425443555344430000000000000010ffffffff0000000000000000001f9b);

        vm.expectRevert();
        contangoLens.irmRaw(positionId);

        IMoneyMarketView moneyMarketView = new SiloMoneyMarketView({
            _moneyMarketId: MM_SILO,
            _contango: IContango(_loadAddress("ContangoProxy")),
            _nativeToken: IWETH9(_loadAddress("NativeToken")),
            _nativeUsdOracle: IAggregatorV2V3(_loadAddress("ChainlinkNativeUsdOracle")),
            _lens: ISiloLens(_loadAddress(string.concat("SiloLens"))),
            _wstEthSilo: ISilo(_loadAddressMaybe(string.concat("Silo_WSTETH_ETH"))),
            _stablecoin: IERC20(_loadAddressMaybe(string.concat("SiloStable")))
        });

        vm.prank(TIMELOCK_ADDRESS);
        contangoLens.setMoneyMarketView(moneyMarketView);

        contangoLens.irmRaw(positionId);
    }

}

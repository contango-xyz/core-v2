//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./AbstractPositionLifeCycle.ft.t.sol";

abstract contract ReferralAbstractPositionLifeCycleFunctional is AbstractPositionLifeCycleFunctional {

    function setUp(Network network, MoneyMarket _mm) internal virtual override {
        super.setUp(network, _mm);

        IReferralManager referralManager = env.feeManager().referralManager();
        vm.prank(TIMELOCK_ADDRESS);
        referralManager.setRewardsAndRebates({ referrerReward: 0.2e4, traderRebate: 0.1e4 });

        address referrer = address(0xbadbeef);
        bytes32 code = keccak256("moo");
        vm.prank(referrer);
        referralManager.registerReferralCode(code);

        vm.prank(TRADER);
        referralManager.setTraderReferralByCode(code);
    }

}

contract ReferralPositionLifeCycleAaveArbitrumFunctional is ReferralAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE);
    }

}

contract ReferralPositionLifeCycleAaveOptimismFunctional is ReferralAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE);
    }

}

contract ReferralPositionLifeCycleAavePolygonFunctional is ReferralAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE);
    }

}

contract ReferralPositionLifeCycleExactlyOptimismFunctional is ReferralAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY);
    }

}

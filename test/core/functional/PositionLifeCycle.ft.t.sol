//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/models/FixedFeeModel.sol";

import "./AbstractPositionLifeCycle.ft.t.sol";

contract PositionLifeCycleAaveArbitrumFunctional is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE);
    }

}

contract PositionLifeCycleAaveOptimismFunctional is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE);
    }

}

contract PositionLifeCycleAavePolygonFunctional is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE);
    }

}

contract PositionLifeCycleExactlyOptimismFunctional is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY);
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./AbstractPositionLifeCycle.ft.t.sol";

contract PositionLifeCycleAaveArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleAaveArbitrumFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleAaveOptimismFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE, WETH, DAI, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleAaveOptimismFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE, DAI, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleAavePolygonFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleAavePolygonFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleExactlyOptimismFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleExactlyOptimismFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

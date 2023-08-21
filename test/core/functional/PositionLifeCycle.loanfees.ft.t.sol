//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../stub/TestFlashLoanProvider.sol";
import "./AbstractPositionLifeCycle.ft.t.sol";

abstract contract LoanFeesAbstractPositionLifeCycleFunctional is AbstractPositionLifeCycleFunctional {

    function setUp(Network network, MoneyMarket _mm) internal virtual override {
        super.setUp(network, _mm);

        // set only the test flash loaner
        Quoter(address(env.quoter())).removeAllFlashLoanProviders();
        Quoter(address(env.quoter())).addFlashLoanProvider(new TestFlashLoanProvider(0.001e4)); // 0.1%
    }

}

contract LoanFeesPositionLifeCycleAaveArbitrumFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE);
    }

}

contract LoanFeesPositionLifeCycleAaveOptimismFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE);
    }

}

contract LoanFeesPositionLifeCycleAavePolygonFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE);
    }

}

contract LoanFeesPositionLifeCycleExactlyOptimismFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY);
    }

}

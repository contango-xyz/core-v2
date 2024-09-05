//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../stub/TestFlashLoanProvider.sol";
import "./AbstractPositionLifeCycle.ft.t.sol";

abstract contract LoanFeesAbstractPositionLifeCycleFunctional is AbstractPositionLifeCycleFunctional {

    function setUp(Network network, MoneyMarketId _mm, bytes32 base, bytes32 quote, uint256 _multiplier) internal virtual override {
        super.setUp(network, _mm, base, quote, _multiplier);

        // set only the test flash loaner
        TestFlashLoanProvider testFlashLoanProvider = new TestFlashLoanProvider(0.01e4); // 1%

        env.tsQuoter().removeAllFlashLoanProviders();
        env.tsQuoter().addFlashLoanProvider(testFlashLoanProvider);
    }

}

contract LoanFeesPositionLifeCycleAaveArbitrumFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract LoanFeesPositionLifeCycleAaveOptimismFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract LoanFeesPositionLifeCycleAavePolygonFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Polygon, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract LoanFeesPositionLifeCycleExactlyOptimismFunctional is LoanFeesAbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

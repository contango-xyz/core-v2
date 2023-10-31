//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

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

contract PositionLifeCycleCompoundMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, MM_COMPOUND, WETH, USDC, WETH_STABLE_MULTIPLIER);

        address oracle = env.compoundComptroller().oracle();
        vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "ETH"), abi.encode(1000e6));
        vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "USDC"), abi.encode(1e6));
    }

}

// TODO find out why it fails and fix, likely due to oracle config
// contract PositionLifeCycleCompoundMainnetFunctionalShort is AbstractPositionLifeCycleFunctional {

//     function setUp() public {
//         super.setUp(Network.Mainnet, MM_COMPOUND, USDC, WETH, STABLE_WETH_MULTIPLIER);

//         address oracle = env.compoundComptroller().oracle();
//         vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "ETH"), abi.encode(1000e6));
//         vm.mockCall(oracle, abi.encodeWithSelector(IUniswapAnchoredView.price.selector, "USDC"), abi.encode(1e6));
//     }

// }

contract PositionLifeCycleSonneOptimismFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_SONNE, WETH, DAI, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleSonneOptimismFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_SONNE, DAI, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleSparkMainnetFunctionalLongDAI is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK, WETH, DAI, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleSparkMainnetFunctionalShortDAI is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK, DAI, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleSparkMainnetFunctionalLongUSDC is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleSparkMainnetFunctionalShortUSDC is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleMorphoBlueGoerliFunctionalLong is AbstractPositionLifeCycleFunctional {

    using MarketParamsLib for MarketParams;

    function setUp() public {
        super.setUp(Network.Goerli, MM_MORPHO_BLUE, WETH, USDC, WETH_STABLE_MULTIPLIER);

        IMorpho morpho = env.morpho();

        // Hack until they deploy the final version
        vm.etch(address(morpho), vm.getDeployedCode("Morpho.sol"));

        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC)),
            irm: IIrm(0x2056d9E6E323Fd06f4344c35022B19849C6402B3),
            lltv: 0.9e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        Payload payload =
            MorphoBlueMoneyMarket(address(contango.positionFactory().moneyMarket(MM_MORPHO_BLUE))).reverseLookup().setMarket(params.id());
        vm.stopPrank();

        env.encoder().setPayload(payload);

        deal(address(instrument.baseData.token), TRADER, 0);
        deal(address(instrument.quoteData.token), TRADER, 0);
    }

}

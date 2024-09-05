//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../stub/MorphoOracleMock.sol";
import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

import "./AbstractPositionLifeCycle.ft.t.sol";

contract PositionLifeCycleAaveArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_AAVE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleExactlyOptimismFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_EXACTLY, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleCompoundMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, MM_COMPOUND, WETH, DAI, WETH_STABLE_MULTIPLIER);

        address oracle = env.compoundComptroller().oracle();
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            abi.encode(1000e18)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IUniswapAnchoredView.getUnderlyingPrice.selector, 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643),
            abi.encode(1e18)
        );
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

contract PositionLifeCycleMorphoBlueMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    using MarketParamsLib for MarketParams;

    function setUp() public {
        super.setUp(Network.Mainnet, 18_919_243, MM_MORPHO_BLUE, WETH, USDC, WETH_STABLE_MULTIPLIER);

        IMorpho morpho = env.morpho();

        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC)),
            irm: IIrm(0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC),
            lltv: 0.86e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        MorphoBlueReverseLookup reverseLookup =
            MorphoBlueMoneyMarket(address(contango.positionFactory().moneyMarket(MM_MORPHO_BLUE))).reverseLookup();
        reverseLookup.setOracle({
            asset: env.token(USDC),
            oracle: address(env.erc20(USDC).chainlinkUsdOracle),
            oracleType: "CHAINLINK",
            oracleCcy: QuoteOracleCcy.USD
        });
        Payload payload = reverseLookup.setMarket(params.id());
        vm.stopPrank();

        env.encoder().setPayload(payload);

        deal(address(instrument.baseData.token), TRADER, 0);
        deal(address(instrument.quoteData.token), TRADER, 0);
    }

}

contract PositionLifeCycleSparkGnosisFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Gnosis, MM_SPARK, WETH, DAI, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleAaveV2MainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, MM_AAVE_V2, WETH, USDC, WETH_STABLE_MULTIPLIER);
        stubChainlinkPrice(0.001e18, 0x986b5E1e1755e3C2440e960477f25201B0a8bbD4);
    }

}

contract PositionLifeCycleRadiantArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, MM_RADIANT, WETH, DAI, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleLodestarArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, 152_284_580, MM_LODESTAR, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleMoonwellBaseFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Base, MM_MOONWELL, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleGranaryOptimismFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Optimism, MM_GRANARY, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleCometBaseFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Base, MM_COMET, WETH, USDC, WETH_STABLE_MULTIPLIER);
        env.encoder().setPayload(Payload.wrap(bytes5(uint40(1))));
    }

}

contract PositionLifeCycleSiloArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, 156_550_831, MM_SILO, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleSiloArbitrumFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, 156_550_831, MM_SILO, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

contract PositionLifeCycleDolomiteArbitrumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, 204_827_569, MM_DOLOMITE, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleDolomiteArbitrumFunctionalShort is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Arbitrum, 204_827_569, MM_DOLOMITE, USDC, WETH, STABLE_WETH_MULTIPLIER);
    }

}

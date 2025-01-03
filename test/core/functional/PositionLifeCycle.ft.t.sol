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

contract PositionLifeCycleSparkSkyMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 18_233_968, MM_SPARK_SKY, WETH, DAI, WETH_STABLE_MULTIPLIER);
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
        Payload payload = reverseLookup.setMarket(params.id());
        vm.stopPrank();

        env.encoder().setPayload(payload);

        deal(address(instrument.baseData.token), TRADER, 0);
        deal(address(instrument.quoteData.token), TRADER, 0);
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

contract PositionLifeCycleCometBaseFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Base, MM_COMET, WETH, USDC, WETH_STABLE_MULTIPLIER);

        CometMoneyMarket mm = CometMoneyMarket(address(contango.positionFactory().moneyMarket(MM_COMET)));

        vm.startPrank(TIMELOCK_ADDRESS);
        Payload payload = mm.reverseLookup().setComet(env.comet());
        vm.stopPrank();

        env.encoder().setPayload(payload);
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

contract PositionLifeCycleZeroLendLineaFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Linea, MM_ZEROLEND, WETH, USDC, WETH_STABLE_MULTIPLIER);
    }

}

contract PositionLifeCycleEulerMainnetFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 20_678_328, MM_EULER, WETH, USDC, WETH_STABLE_MULTIPLIER);

        EulerMoneyMarket mm = EulerMoneyMarket(address(contango.positionFactory().moneyMarket(MM_EULER)));

        IEulerVault ethVault = IEulerVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2);
        IEulerVault usdcVault = IEulerVault(0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9);

        vm.startPrank(TIMELOCK_ADDRESS);
        uint16 ethId = mm.reverseLookup().setVault(ethVault);
        uint16 usdcId = mm.reverseLookup().setVault(usdcVault);
        vm.stopPrank();

        env.encoder().setPayload(baseQuotePayload(ethId, usdcId));
    }

}

contract PositionLifeCycleFluidEthereumFunctionalLong is AbstractPositionLifeCycleFunctional {

    function setUp() public {
        super.setUp(Network.Mainnet, 20_714_207, MM_FLUID, WETH, USDC, WETH_STABLE_MULTIPLIER);
        env.encoder().setPayload(Payload.wrap(bytes5(uint40(11))));
        stubChainlinkPrice(0.001e18, CHAINLINK_USDC_ETH);
    }

}

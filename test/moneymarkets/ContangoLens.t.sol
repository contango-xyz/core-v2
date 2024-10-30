//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

contract ContangoLensTest is Test {

    Env internal env;
    ContangoLens internal sut;
    PositionNFT internal positionNFT;
    PositionId internal positionId;
    TestInstrument internal instrument;

    MoneyMarketId internal constant mm = MM_AAVE;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(254_125_507);

        sut = env.contangoLens();
        positionNFT = sut.positionNFT();

        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
    }

    function testLeverage_NoPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        assertEq(sut.leverage(positionId), 0);
    }

    function testLeverage_ValidPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 1);
        vm.mockCall(address(positionNFT), abi.encodeWithSelector(PositionNFT.exists.selector, positionId), abi.encode(true));
        vm.mockCall(
            address(sut.moneyMarketViews(mm)),
            abi.encodeWithSelector(IMoneyMarketView.balances.selector, positionId),
            abi.encode(1 ether, 750e6) // 2x leverage
        );
        vm.mockCall(
            address(sut.moneyMarketViews(mm)),
            abi.encodeWithSelector(IMoneyMarketView.prices.selector, positionId),
            abi.encode(1000e8, 1e8, 1e8)
        );

        assertEq(sut.leverage(positionId), 4e18);
    }

    function testNetRate_NoPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 0);
        assertEq(sut.netRate(positionId), 0);
    }

    function testNetRate_ValidPosition() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 1);
        vm.mockCall(address(positionNFT), abi.encodeWithSelector(PositionNFT.exists.selector, positionId), abi.encode(true));
        vm.mockCall(
            address(sut.moneyMarketViews(mm)),
            abi.encodeWithSelector(IMoneyMarketView.rates.selector, positionId),
            abi.encode(0.1e18, 0.01e18)
        );
        vm.mockCall(
            address(sut.moneyMarketViews(mm)),
            abi.encodeWithSelector(IMoneyMarketView.balances.selector, positionId),
            abi.encode(1 ether, 500e6) // 2x leverage
        );
        vm.mockCall(
            address(sut.moneyMarketViews(mm)),
            abi.encodeWithSelector(IMoneyMarketView.prices.selector, positionId),
            abi.encode(1000e8, 1e8, 1e8)
        );

        assertEq(sut.netRate(positionId), -0.04e18); // 4% net rate => 1% (lending rate) 10% / 2x (borrowing rate / leverage)
    }

    function testMetaData_Aave() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, mm, PERP, 1);
        sut.metaData(positionId);
    }

    function testMetaData_Lodestar() public {
        positionId = env.encoder().encodePositionId(instrument.symbol, MM_LODESTAR, PERP, 1);
        sut.metaData(positionId);
    }

}

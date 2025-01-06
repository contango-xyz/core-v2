//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";

contract MorphoBlueMoneyMarketWSTETHTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for *;

    Env internal env;
    MorphoBlueMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    IMorpho internal morpho;
    MorphoBlueReverseLookup internal reverseLookup;
    address trader;

    uint256 chainlinkDecimals = 8;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(18_919_630);

        trader = makeAddr("trader");

        contango = address(env.contango());

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        morpho = sut.morpho();
        reverseLookup = sut.reverseLookup();

        MarketParams memory params =
            morpho.idToMarketParams(MorphoMarketId.wrap(0xc54d7acf14de29e0e5527cabd7a576506870346a78a11a6762e2cca66322ec41));
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(WETH), lp, 100 ether, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100 ether, shares: 0, onBehalf: lp, data: "" });

        vm.startPrank(Timelock.unwrap(TIMELOCK));
        Payload payload = reverseLookup.setMarket(params.id());
        vm.stopPrank();

        env.createInstrument(env.erc20(WSTETH), env.erc20(WETH));

        positionId = encode(Symbol.wrap("WSTETHWETH"), MM_MORPHO_BLUE, PERP, 1, payload);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WSTETH), env.token(WETH));
        vm.stopPrank();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1150e8, address(env.erc20(WSTETH).chainlinkUsdOracle));
        stubChainlinkPrice(1.15e18, 0x86392dC19c0b719886221c78AB11eb8Cf5c52812); // stETH / ETH
        stubChainlinkPrice(1e8, address(env.erc20(WETH).chainlinkUsdOracle));
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WSTETH);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WSTETHWETH"), MM_MORPHO_BLUE, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WSTETH);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WSTETHWETH"), MM_EXACTLY, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WSTETH);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 1 ether;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        sut.lend(positionId, lendToken, lendAmount);

        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, lendToken.decimals(), "collateralBalance after lend + borrow"
        );

        // borrow
        vm.prank(contango);
        sut.borrow(positionId, borrowToken, borrowAmount, trader);
        assertEqDecimal(borrowToken.balanceOf(trader), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, trader);

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(trader), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testLifeCycle_RepayInExcess() public {
        // setup
        IERC20 lendToken = env.token(WSTETH);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 1 ether;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, lendToken.decimals(), "collateralBalance after lend + borrow"
        );

        // borrow
        vm.prank(contango);
        sut.borrow(positionId, borrowToken, borrowAmount, trader);
        assertEqDecimal(borrowToken.balanceOf(trader), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, trader);

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(trader), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testRepayEmptyPosition() public {
        IERC20 borrowToken = env.token(WETH);
        env.dealAndApprove(borrowToken, contango, 1 ether, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 1 ether);
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(WSTETH);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 1 ether;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        sut.lend(positionId, lendToken, lendAmount);

        // borrow
        vm.prank(contango);
        sut.borrow(positionId, borrowToken, borrowAmount, trader);
        assertEqDecimal(borrowToken.balanceOf(trader), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));

        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(sut.debtBalance(positionId, borrowToken), debt / 4 * 3, 5, borrowToken.decimals(), "debt is 3/4");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral / 4, trader);

        assertEq(withdrew, collateral / 4, "withdrew half collateral");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), collateral / 4 * 3, 5, lendToken.decimals(), "collateral is 3/4"
        );
        assertEqDecimal(lendToken.balanceOf(trader), collateral / 4, lendToken.decimals(), "withdrawn balance");
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

import { MarketParamsLib } from "src/moneymarkets/morpho/dependencies/MarketParamsLib.sol";
import "../../stub/MorphoOracleMock.sol";

import { Morpho } from "@morpho-blue/Morpho.sol"; // Import so the compiler knows about it

contract MorphoBlueMoneyMarketGoerliTest is Test {

    using Address for *;
    using ERC20Lib for *;
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    Env internal env;
    MorphoBlueMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    IMorpho internal morpho;
    MorphoBlueReverseLookup internal reverseLookup;
    address trader;

    uint256 chainlinkDecimals = 8;

    function setUp() public {
        env = provider(Network.Goerli);
        env.init();

        trader = makeAddr("trader");

        contango = address(env.contango());

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        morpho = sut.morpho();
        reverseLookup = sut.reverseLookup();

        // Hack until they deploy the final version
        vm.etch(address(morpho), vm.getDeployedCode("Morpho.sol"));

        MorphoOracleMock oracle = new MorphoOracleMock(env.erc20(WETH), env.erc20(USDC));
        MarketParams memory params = MarketParams({
            loanToken: env.token(USDC),
            collateralToken: env.token(WETH),
            oracle: oracle,
            irm: IIrm(0x2056d9E6E323Fd06f4344c35022B19849C6402B3),
            lltv: 0.9e18
        });
        morpho.createMarket(params);
        address lp = makeAddr("LP");
        env.dealAndApprove(env.token(USDC), lp, 100_000e6, address(morpho));
        vm.prank(lp);
        morpho.supply({ marketParams: params, assets: 100_000e6, shares: 0, onBehalf: lp, data: "" });

        vm.prank(Timelock.unwrap(TIMELOCK));
        Payload payload = reverseLookup.setMarket(params.id());

        env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        positionId = encode(Symbol.wrap("WETHUSDC"), MM_MORPHO_BLUE, PERP, 1, payload);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WETH), env.token(USDC));
        vm.stopPrank();

        env.spotStub().stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        env.spotStub().stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_MORPHO_BLUE, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployMorphoBlueMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

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

        assertApproxEqAbsDecimal(debtBalance(), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow");

        skip(10 days);

        // repay
        uint256 debt = debtBalance();
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(debtBalance(), 0, borrowToken.decimals(), "debt is zero");

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
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

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

        assertApproxEqAbsDecimal(debtBalance(), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow");

        skip(10 days);

        // repay
        uint256 debt = debtBalance();
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(debtBalance(), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, trader);

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(trader), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

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
        assertApproxEqAbsDecimal(debtBalance(), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow");

        skip(10 days);

        // repay
        uint256 debt = debtBalance();
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));

        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(debtBalance(), debt / 4 * 3, 5, borrowToken.decimals(), "debt is 3/4");

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

    function testIERC165() public {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

    function debtBalance() internal returns (uint256 debt) {
        Id marketId = reverseLookup.marketId(positionId.getPayload());
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        morpho.accrueInterest(marketParams); // Accrue interest before before loading the market state
        Market memory market = morpho.market(marketId);
        (, debt,) = morpho.position(marketId, address(sut));
        debt = debt.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
    }

}

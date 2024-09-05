//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";
import "../../BaseTest.sol";

contract CompoundMoneyMarketTest is BaseTest {

    using ERC20Lib for *;

    Env internal env;
    CompoundMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;

    uint256 chainlinkDecimals = 8;
    uint256 compoundPrecision = 0.00000001e18;

    IERC20 internal comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init();

        contango = address(env.contango());

        sut = env.deployer().deployCompoundMoneyMarket(env, env.contango());

        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_COMPOUND, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WETH), env.token(USDC));
        vm.stopPrank();

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

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployCompoundMoneyMarket(env, env.contango());
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_COMPOUND, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployCompoundMoneyMarket(env, env.contango());
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_WETHUSDC() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        CompoundMoneyMarket emm = env.deployer().deployCompoundMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        emm.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(emm), address(emm.cToken(lendToken))), 0, "lendToken allowance");
        assertEq(borrowToken.allowance(address(emm), address(emm.cToken(borrowToken))), type(uint256).max, "borrowToken allowance");
    }

    function testInitialise_USDCWETH() public {
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WETH);

        CompoundMoneyMarket emm = env.deployer().deployCompoundMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        emm.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(emm), address(emm.cToken(lendToken))), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(emm), address(emm.cToken(borrowToken))), 0, "borrowToken allowance");
    }

    function testInitialise_USDCDAI() public {
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(DAI);

        CompoundMoneyMarket emm = env.deployer().deployCompoundMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        emm.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(emm), address(emm.cToken(lendToken))), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(emm), address(emm.cToken(borrowToken))), type(uint256).max, "borrowToken allowance");
    }

    function testLifeCycle_HP_WETHUSDC() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqRelDecimal(
            sut.collateralBalance(positionId, lendToken),
            lendAmount,
            compoundPrecision,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertApproxEqRelDecimal(
            _debt(borrowToken), borrowAmount, compoundPrecision, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skipWithBlock(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(comp.balanceOf(address(this)), 0.006625021599845406e18, comp.decimals(), "comp.balanceOf");

        skipWithBlock(20 days);

        // repay
        uint256 debt = _debt(borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(_debt(borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertLt(sut.collateralBalance(positionId, lendToken), compoundPrecision, "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(comp.balanceOf(address(this)), 0.01545838372161743e18, comp.decimals(), "comp.balanceOf");
    }

    function testLifeCycle_HP_USDCWETH() public {
        // setup
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deployCompoundMoneyMarket(env, env.contango());
        positionId = env.encoder().encodePositionId(Symbol.wrap("USDCWETH"), MM_COMPOUND, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
        vm.stopPrank();

        uint256 lendAmount = 10_000e6;
        uint256 borrowAmount = 1 ether;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqRelDecimal(
            sut.collateralBalance(positionId, lendToken),
            lendAmount,
            compoundPrecision,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertApproxEqRelDecimal(
            _debt(borrowToken), borrowAmount, compoundPrecision, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skipWithBlock(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(comp.balanceOf(address(this)), 0.035146253568964222e18, comp.decimals(), "comp.balanceOf");

        skipWithBlock(20 days);

        // repay
        uint256 debt = _debt(borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(_debt(borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertLt(sut.collateralBalance(positionId, lendToken), compoundPrecision, "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(comp.balanceOf(address(this)), 0.082007924994249851e18, comp.decimals(), "comp.balanceOf");
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
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqRelDecimal(
            sut.collateralBalance(positionId, lendToken),
            lendAmount,
            compoundPrecision,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertApproxEqRelDecimal(
            _debt(borrowToken), borrowAmount, compoundPrecision, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skipWithBlock(10 days);

        // repay
        uint256 debt = _debt(borrowToken);
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(_debt(borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertLt(sut.collateralBalance(positionId, lendToken), compoundPrecision, "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testRepayEmptyPosition() public {
        IERC20 borrowToken = env.token(USDC);
        env.dealAndApprove(borrowToken, contango, 10e6, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 10e6);
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
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqRelDecimal(
            sut.collateralBalance(positionId, lendToken),
            lendAmount,
            compoundPrecision,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertApproxEqRelDecimal(
            _debt(borrowToken), borrowAmount, compoundPrecision, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skipWithBlock(10 days);

        // repay
        uint256 debt = _debt(borrowToken);
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqRelDecimal(_debt(borrowToken), debt / 4 * 3, compoundPrecision, borrowToken.decimals(), "debt is 3/4");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral / 4, address(this));

        assertEq(withdrew, collateral / 4, "withdrew half collateral");
        assertApproxEqRelDecimal(
            sut.collateralBalance(positionId, lendToken), collateral / 4 * 3, compoundPrecision, lendToken.decimals(), "collateral is 3/4"
        );
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral / 4, lendToken.decimals(), "withdrawn balance");
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

    function _debt(IERC20 borrowToken) internal returns (uint256) {
        return sut.cToken(borrowToken).borrowBalanceCurrent(address(sut));
    }

}

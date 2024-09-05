//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract ExactlyMoneyMarketTest is Test {

    using ERC20Lib for *;

    event MarketEntered(IExactlyMarket indexed market, address indexed account);

    Env internal env;
    ExactlyMoneyMarket internal sut;
    ExactlyReverseLookup internal reverseLookup;
    PositionId internal positionId;
    address internal contango;

    uint256 chainlinkDecimals = 8;

    IERC20 internal op = IERC20(0x4200000000000000000000000000000000000042);
    IERC20 internal exa = IERC20(0x1e925De1c68ef83bD98eE3E130eF14a50309C01B);

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();

        contango = address(env.contango());

        sut = env.deployer().deployExactlyMoneyMarket(env, env.contango());
        reverseLookup = sut.reverseLookup();

        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WETH), env.token(USDC));
        vm.stopPrank();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployExactlyMoneyMarket(env, env.contango());
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployExactlyMoneyMarket(env, env.contango());
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_AAVE, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        ExactlyMoneyMarket emm = env.deployer().deployExactlyMoneyMarket(env, IContango(contango));
        IExactlyMarket lendMarket = reverseLookup.market(lendToken);

        vm.expectEmit(true, true, true, true);
        emit MarketEntered(lendMarket, address(emm));
        vm.prank(contango);
        emm.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(emm), address(lendMarket)), type(uint256).max, "lendToken allowance");
        assertEq(
            borrowToken.allowance(address(emm), address(reverseLookup.market(borrowToken))), type(uint256).max, "borrowToken allowance"
        );
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);
        IExactlyMarket borrowMarket = reverseLookup.market(borrowToken);

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

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            borrowMarket.previewDebt(address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(op.balanceOf(address(this)), 13.209375993198303002e18, op.decimals(), "op.balanceOf");
        assertEqDecimal(exa.balanceOf(address(this)), 3.146489565360132586e18, exa.decimals(), "exa.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = borrowMarket.previewDebt(address(sut));
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(borrowMarket.previewDebt(address(sut)), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(op.balanceOf(address(this)), 24.502211551239104358e18, op.decimals(), "op.balanceOf");
        assertEqDecimal(exa.balanceOf(address(this)), 5.834370018224787436e18, exa.decimals(), "exa.balanceOf");
    }

    function testLifeCycle_RepayInExcess() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);
        IExactlyMarket borrowMarket = reverseLookup.market(borrowToken);

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

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            borrowMarket.previewDebt(address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = borrowMarket.previewDebt(address(sut));
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(borrowMarket.previewDebt(address(sut)), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
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
        IExactlyMarket borrowMarket = reverseLookup.market(borrowToken);

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

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            borrowMarket.previewDebt(address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = borrowMarket.previewDebt(address(sut));
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(borrowMarket.previewDebt(address(sut)), debt / 4 * 3, 5, borrowToken.decimals(), "debt is 3/4");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral / 4, address(this));

        assertEq(withdrew, collateral / 4, "withdrew half collateral");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), collateral / 4 * 3, 5, lendToken.decimals(), "collateral is 3/4"
        );
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral / 4, lendToken.decimals(), "withdrawn balance");
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

}

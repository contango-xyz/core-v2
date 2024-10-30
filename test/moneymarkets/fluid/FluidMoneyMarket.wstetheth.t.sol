//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract FluidMoneyMarketWSTETHETHTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    FluidMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;

    address trader;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(20_714_207);

        contango = address(env.contango());

        sut = FluidMoneyMarket(payable(address(env.positionFactory().moneyMarket(MM_FLUID))));
        env.createInstrument(env.erc20(WSTETH), env.erc20(WETH));

        trader = makeAddr("trader");

        positionId = encode(Symbol.wrap("WSTETHWETH"), MM_FLUID, PERP, 0, Payload.wrap(bytes5(uint40(3))));

        vm.startPrank(contango);
        sut = FluidMoneyMarket(payable(address(env.positionFactory().createUnderlyingPosition(positionId))));
        sut.initialise(positionId, env.token(WSTETH), env.token(WETH));
        vm.stopPrank();
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
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 200, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken),
            borrowAmount,
            0.000000001e18,
            borrowToken.decimals(),
            "debtBalance after lend + borrow"
        );

        skip(15 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken) + 0.000000001e18;
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertApproxEqAbsDecimal(repaid, debt, 0.000000001e18, borrowToken.decimals(), "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertApproxEqAbsDecimal(withdrew, collateral, 1, lendToken.decimals(), "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertApproxEqAbsDecimal(lendToken.balanceOf(address(this)), collateral, 1, lendToken.decimals(), "withdrawn balance");

        // vm.prank(contango);
        // sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        // assertEqDecimal(rewardToken.balanceOf(address(this)), 548.173776455026455026e18, 18, "rewards balance");
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
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 200, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken),
            borrowAmount,
            0.000000001e18,
            borrowToken.decimals(),
            "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertApproxEqAbsDecimal(repaid, debt, 0.000000001e18, borrowToken.decimals(), "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertApproxEqAbsDecimal(withdrew, collateral, 1, lendToken.decimals(), "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertApproxEqAbsDecimal(lendToken.balanceOf(address(this)), collateral, 1, lendToken.decimals(), "withdrawn balance");
    }

    function testRepayEmptyPosition() public {
        IERC20 borrowToken = env.token(WETH);
        env.dealAndApprove(borrowToken, contango, 10e6, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 10e6);
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
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 200, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken),
            borrowAmount,
            0.000000001e18,
            borrowToken.decimals(),
            "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), debt / 4 * 3, 0.000000001e18, borrowToken.decimals(), "debt is 3/4"
        );

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral / 4, address(this));

        assertEq(withdrew, collateral / 4, "withdrew half collateral");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), collateral / 4 * 3, 0.000000001e18, lendToken.decimals(), "collateral is 3/4"
        );
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral / 4, lendToken.decimals(), "withdrawn balance");
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../TestSetup.t.sol";

contract SiloMoneyMarketArbitrumTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    SiloMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    ISilo internal silo;
    ISiloLens internal siloLens;

    IERC20 internal arb;

    uint256 chainlinkDecimals = 8;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(156_550_831);

        contango = address(env.contango());

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        siloLens = sut.LENS();
        silo = sut.repository().getSilo(env.token(WBTC));
        arb = env.token(ARB);

        env.createInstrument(env.erc20(WBTC), env.erc20(USDC));

        positionId = env.encoder().encodePositionId(Symbol.wrap("WBTCUSDC"), MM_SILO, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WBTC), env.token(USDC));
        vm.stopPrank();

        env.spotStub().stubChainlinkPrice(10_000e8, address(env.erc20(WBTC).chainlinkUsdOracle));
        env.spotStub().stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
        // Silo's oracle is ETH based, so we need a live ETH price
        env.spotStub().stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WBTCUSDC"), MM_SILO, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WBTCUSDC"), MM_EXACTLY, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise() public {
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(sut), address(silo)), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(sut), address(silo)), type(uint256).max, "borrowToken allowance");
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 1e8;
        uint256 borrowAmount = 5000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            debtBalance(borrowToken, address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(arb.balanceOf(address(this)), 18.683167312278374115e18, arb.decimals(), "arb.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = debtBalance(borrowToken, address(sut));
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(debtBalance(borrowToken, address(sut)), 0, borrowToken.decimals(), "debt is zero");

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
        assertEqDecimal(arb.balanceOf(address(this)), 43.594057061982872935e18, arb.decimals(), "arb.balanceOf");
    }

    function testLifeCycle_RepayInExcess() public {
        // setup
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 1e8;
        uint256 borrowAmount = 5000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            debtBalance(borrowToken, address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = debtBalance(borrowToken, address(sut));
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, 5010.493031e6, "repaid all debt");
        assertEqDecimal(debtBalance(borrowToken, address(sut)), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 1e8;
        uint256 borrowAmount = 5000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            debtBalance(borrowToken, address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = debtBalance(borrowToken, address(sut));
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(debtBalance(borrowToken, address(sut)), debt / 4 * 3, 5, borrowToken.decimals(), "debt is 3/4");

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

    function testIERC165() public {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

    function debtBalance(IERC20 asset, address account) internal view returns (uint256) {
        return siloLens.getBorrowAmount(silo, asset, account, block.timestamp);
    }

    function testLifeCycle_HP_WETHUSDC() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        silo = sut.WSTETH_SILO();

        env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_SILO, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
        vm.stopPrank();

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 5000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            debtBalance(borrowToken, address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(arb.balanceOf(address(this)), 49.672173471918924618e18, arb.decimals(), "arb.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = debtBalance(borrowToken, address(sut));
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(debtBalance(borrowToken, address(sut)), 0, borrowToken.decimals(), "debt is zero");

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
        assertEqDecimal(arb.balanceOf(address(this)), 115.901738101144157445e18, arb.decimals(), "arb.balanceOf");
    }

    function testLifeCycle_HP_USDCWETH() public {
        // setup
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        silo = sut.WSTETH_SILO();

        env.createInstrument(env.erc20(USDC), env.erc20(WETH));

        positionId = env.encoder().encodePositionId(Symbol.wrap("USDCWETH"), MM_SILO, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
        vm.stopPrank();

        uint256 lendAmount = 10_000e6;
        uint256 borrowAmount = 5 ether;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            debtBalance(borrowToken, address(sut)), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(arb.balanceOf(address(this)), 28.153748214351772757e18, arb.decimals(), "arb.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = debtBalance(borrowToken, address(sut));
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(debtBalance(borrowToken, address(sut)), 0, borrowToken.decimals(), "debt is zero");

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
        assertEqDecimal(arb.balanceOf(address(this)), 65.6920791668208031e18, arb.decimals(), "arb.balanceOf");
    }

}

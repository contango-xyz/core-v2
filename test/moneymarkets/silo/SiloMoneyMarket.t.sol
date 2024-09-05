//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

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

    IERC20 internal siloToken;
    IERC20 internal wstETH = IERC20(0x5979D7b546E38E414F7E9822514be443A4800529);

    uint256 chainlinkDecimals = 8;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(195_468_081);

        contango = address(env.contango());

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        siloLens = sut.lens();
        silo = sut.repository().getSilo(env.token(WBTC));
        siloToken = IERC20(0x0341C0C0ec423328621788d4854119B97f44E391);

        env.createInstrument(env.erc20(WBTC), env.erc20(USDC));

        positionId = env.encoder().encodePositionId(Symbol.wrap("WBTCUSDC"), MM_SILO, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WBTC), env.token(USDC));
        vm.stopPrank();

        stubChainlinkPrice(10_000e8, address(env.erc20(WBTC).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
        // Silo's oracle is ETH based, so we need a live ETH price
        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
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

    function testGetSilo() public view {
        assertEq(address(sut.getSilo(env.token(WETH), env.token(USDC)).siloAsset()), address(wstETH), "WETH/USDC silo");
        assertEq(address(sut.getSilo(env.token(USDC), env.token(WETH)).siloAsset()), address(wstETH), "USDC/WETH silo");

        assertEq(address(sut.getSilo(env.token(WBTC), env.token(USDC)).siloAsset()), address(env.token(WBTC)), "WBTC/USDC silo");
        assertEq(address(sut.getSilo(env.token(USDC), env.token(WBTC)).siloAsset()), address(env.token(WBTC)), "USDC/WBTC silo");
    }

    function testInitialise_WBTCUSDC() public {
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(address(sut.silo().siloAsset()), address(env.token(WBTC)), "Selected silo");
        assertEq(lendToken.allowance(address(sut), address(silo)), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(sut), address(silo)), type(uint256).max, "borrowToken allowance");
    }

    function testInitialise_USDCWBTC() public {
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WBTC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(address(sut.silo().siloAsset()), address(env.token(WBTC)), "Selected silo");
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
            sut.debtBalance(positionId, borrowToken), borrowAmount, 2, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 0, siloToken.decimals(), "siloToken.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        assertGt(collateral, lendAmount, "collateral didn't grew");
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 0, siloToken.decimals(), "siloToken.balanceOf");
    }

    function testLifeCycle_HP_collateralOnly() public {
        // setup
        IERC20 lendToken = env.token(WBTC);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 1e8;
        uint256 borrowAmount = 5000e6;

        positionId = encode(Symbol.wrap("WBTCUSDC"), MM_SILO, PERP, 1, setBit("", COLLATERAL_ONLY));

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
            sut.debtBalance(positionId, borrowToken), borrowAmount, 2, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 0, siloToken.decimals(), "siloToken.balanceOf");

        skip(20 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        assertEq(collateral, lendAmount, "collateral grew");
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 0, siloToken.decimals(), "siloToken.balanceOf");
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
            sut.collateralBalance(positionId, lendToken), lendAmount, 2, lendToken.decimals(), "collateralBalance after lend "
        );

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 2, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEqDecimal(repaid, 5028.942132e6, borrowToken.decimals(), "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

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
            sut.debtBalance(positionId, borrowToken), borrowAmount, 2, borrowToken.decimals(), "debtBalance after borrow"
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

    function testLifeCycle_HP_WETHUSDC() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        silo = sut.wstEthSilo();

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
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 370.743007939768057968e18, siloToken.decimals(), "siloToken.balanceOf");

        skip(20 days);

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
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 765.352883082794440661e18, siloToken.decimals(), "siloToken.balanceOf");
    }

    function testLifeCycle_HP_USDCWETH() public {
        // setup
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deploySiloMoneyMarket(env, IContango(contango));
        silo = sut.wstEthSilo();

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
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after borrow"
        );

        skip(15 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 202.989121796373565969e18, siloToken.decimals(), "siloToken.balanceOf");

        skip(20 days);

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
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        // Claim rewards after closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(siloToken.balanceOf(address(this)), 419.045824935797473745e18, siloToken.decimals(), "siloToken.balanceOf");
    }

}

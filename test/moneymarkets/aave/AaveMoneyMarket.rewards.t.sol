//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract AaveMoneyMarketRewardsTest is Test {

    using ERC20Lib for *;

    Env internal env;
    AaveMoneyMarket internal sut;
    PositionId internal positionId;
    IPool internal pool;

    uint256 chainlinkDecimals = 8;

    address contango;

    IERC20 internal stMatic = IERC20(0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4);
    IERC20 internal maticX = IERC20(0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6);

    function setUp() public {
        env = provider(Network.Polygon);
        env.init();

        contango = address(env.contango());

        sut = env.deployer().deployAaveMoneyMarket(env, env.contango());
        pool = AaveMoneyMarketView(address(sut)).pool();
        positionId = env.encoder().encodePositionId(Symbol.wrap("USDCWMATIC"), MM_AAVE, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(USDC), env.token(WMATIC));
        vm.stopPrank();

        stubChainlinkPrice(1000e8, address(env.erc20(USDC).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(WMATIC).chainlinkUsdOracle));
    }

    function testLifeCycle_ClaimRewards() public {
        // setup
        IERC20 lendToken = env.token(USDC);
        IERC20 borrowToken = env.token(WMATIC);

        uint256 lendAmount = 1000e6;
        uint256 borrowAmount = 500e18;

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

        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), borrowAmount, borrowToken.decimals(), "debtBalance after lend + borrow");

        skip(10 days);

        // Claim rewards without closing position
        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, contango);
        assertEqDecimal(stMatic.balanceOf(contango), 0.042778554603008725e18, stMatic.decimals(), "stMatic.balanceOf");
        assertEqDecimal(maticX.balanceOf(contango), 0.042778554603008725e18, maticX.decimals(), "maticX.balanceOf");

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
        sut.claimRewards(positionId, lendToken, borrowToken, contango);
        assertEqDecimal(stMatic.balanceOf(contango), 0.081822798852697848e18, stMatic.decimals(), "stMatic.balanceOf");
        assertEqDecimal(maticX.balanceOf(contango), 0.128335663809026175e18, maticX.decimals(), "maticX.balanceOf");
    }

}

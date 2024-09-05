//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract DolomiteMoneyMarketArbitrumIsolationTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    DolomiteMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    IDolomiteMargin internal dolomite;
    IERC20 internal isolationToken;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(203_041_671);

        contango = address(env.contango());

        sut = env.deployer().deployDolomiteMoneyMarket(env, IContango(contango));
        dolomite = env.dolomite();
        env.createInstrument(env.erc20(PTweETH27JUN2024), env.erc20(WETH));

        Payload payload = Payload.wrap(bytes5(uint40(42)));
        positionId = encode(Symbol.wrap("PTeETHF24WETH"), MM_DOLOMITE, PERP, 1, payload);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(PTweETH27JUN2024), env.token(WETH));
        vm.stopPrank();

        isolationToken = IERC20(0x6Cc56e9cA71147D40b10a8cB8cBe911C1Faf4Cf8);

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        vm.mockCall(
            0xBfca44aB734E57Dc823cA609a0714EeC9ED06cA0, abi.encodeWithSignature("getPrice(address)", isolationToken), abi.encode(970e18)
        );
    }

    function testInitialise() public {
        IERC20 lendToken = env.token(PTweETH27JUN2024);
        IERC20 borrowToken = env.token(WETH);

        sut = env.deployer().deployDolomiteMoneyMarket(env, IContango(contango));

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(sut), address(dolomite)), 0, "lendToken allowance");
        assertEq(borrowToken.allowance(address(sut), address(dolomite)), type(uint256).max, "borrowToken allowance");

        IIsolationVault isolationVault = sut.vault();
        assertFalse(address(isolationVault) == address(0), "isolationVault wasn't created");
        assertEq(lendToken.allowance(address(sut), address(isolationVault)), type(uint256).max, "isolationToken allowance");
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(PTweETH27JUN2024);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 8 ether;

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
    }

    function testLifeCycle_RepayInExcess() public {
        // setup
        IERC20 lendToken = env.token(PTweETH27JUN2024);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 8 ether;

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
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testRepayEmptyPosition() public {
        IERC20 borrowToken = env.token(WETH);
        env.dealAndApprove(borrowToken, contango, 10e6, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 10e6);
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(PTweETH27JUN2024);
        IERC20 borrowToken = env.token(WETH);

        uint256 lendAmount = 10e18;
        uint256 borrowAmount = 8 ether;

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

}

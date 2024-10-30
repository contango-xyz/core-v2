//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../TestSetup.t.sol";

contract AaveMoneyMarketPolygonTest is Test {

    using ERC20Lib for *;

    Env internal env;
    AaveMoneyMarket internal sut;
    PositionId internal positionId;
    IPool internal pool;

    uint256 chainlinkDecimals = 8;

    address contango;

    function setUp() public {
        env = provider(Network.Polygon);
        env.init(62_786_660);

        contango = address(env.contango());

        sut = env.deployer().deployAaveMoneyMarket(env, env.contango());
        pool = AaveMoneyMarketView(address(sut)).pool();
    }

    function testLifeCycle_IsolationMode() public {
        // setup
        IERC20 lendToken = IERC20(0xE111178A87A3BFf0c8d18DECBa5798827539Ae99); //EURS
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10_000e2;
        uint256 borrowAmount = 5000e6;

        sut = env.deployer().deployAaveMoneyMarket(env, IContango(contango));
        vm.prank(TIMELOCK_ADDRESS);
        IContango(contango).createInstrument(Symbol.wrap("EURSUSDC"), lendToken, borrowToken);
        positionId = encode(Symbol.wrap("EURSUSDC"), MM_AAVE, PERP, 1, flagsAndPayload(setBit("", ISOLATION_MODE), ""));
        vm.startPrank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
        vm.stopPrank();

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

    function testLifeCycle_IsolationMode_EMode() public {
        // setup
        IERC20 lendToken = IERC20(0xE111178A87A3BFf0c8d18DECBa5798827539Ae99); //EURS
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10_000e2;
        uint256 borrowAmount = 9000e6;

        sut = env.deployer().deployAaveMoneyMarket(env, IContango(contango));
        vm.prank(TIMELOCK_ADDRESS);
        IContango(contango).createInstrument(Symbol.wrap("EURSUSDC"), lendToken, borrowToken);
        positionId = encode(
            Symbol.wrap("EURSUSDC"), MM_AAVE, PERP, 1, flagsAndPayload(setBit(setBit("", E_MODE), ISOLATION_MODE), bytes4(uint32(1)))
        );
        vm.startPrank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
        vm.stopPrank();

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

}

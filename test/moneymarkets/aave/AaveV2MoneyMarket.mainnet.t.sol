//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract AaveV2MoneyMarketMainnetTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    AaveMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    IPool internal pool;

    uint256 chainlinkDecimals = 8;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init();

        contango = address(env.contango());

        sut = env.deployer().deployAaveV2MoneyMarket(env, IContango(contango));
        pool = AaveMoneyMarketView(address(sut)).pool();
        env.createInstrument(env.erc20(WETH), env.erc20(DAI));

        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHDAI"), MM_AAVE_V2, PERP, 1);
        vm.startPrank(contango);
        sut.initialise(positionId, env.token(WETH), env.token(DAI));
        vm.stopPrank();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(DAI).chainlinkUsdOracle));
    }

    function testMoneyMarketPermissions() public {
        address hacker = address(0x666);

        IERC20 borrowToken = env.token(DAI);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.flashBorrow(positionId, borrowToken, 0, "", Contango(contango).completeOpenFromFlashBorrow);
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        sut = env.deployer().deployAaveV2MoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHDAI"), MM_AAVE_V2, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        sut = env.deployer().deployAaveV2MoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHDAI"), MM_COMPOUND, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_NoEMode() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        sut = env.deployer().deployAaveV2MoneyMarket(env, IContango(contango));

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(sut), address(pool)), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(sut), address(pool)), type(uint256).max, "borrowToken allowance");
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e18;

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
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e18;

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
        IERC20 borrowToken = env.token(DAI);
        env.dealAndApprove(borrowToken, contango, 10e18, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 10e18);
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e18;

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

    function testLifeCycle_FlashBorrow() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(DAI);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e18;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        bytes memory result = sut.flashBorrow(positionId, borrowToken, borrowAmount, "", this.callback);
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");
        assertEq(result, "Hello world!", "callback result");

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

    function testFlashLoanCallbackValidations() public {
        vm.expectRevert(abi.encodeWithSelector(IFlashBorrowProvider.InvalidSenderOrInitiator.selector));
        IFlashLoanReceiver(address(sut)).executeOperation({
            assets: toArray(address(0)),
            amounts: toArray(0),
            premiums: toArray(0),
            initiator: address(0),
            params: ""
        });

        vm.prank(address(sut.pool()));
        vm.expectRevert(abi.encodeWithSelector(IFlashBorrowProvider.InvalidSenderOrInitiator.selector));
        IFlashLoanReceiver(address(sut)).executeOperation({
            assets: toArray(address(0)),
            amounts: toArray(0),
            premiums: toArray(0),
            initiator: address(0),
            params: ""
        });
    }

    function callback(IERC20 asset, uint256 amount, bytes memory) external view returns (bytes memory) {
        assertEqDecimal(asset.balanceOf(address(this)), amount, IERC20(address(asset)).decimals(), "borrowed balance");
        // Do nothing with the money
        return "Hello world!";
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertTrue(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

}

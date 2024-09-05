//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract DolomiteMoneyMarketArbitrumIsolationBugFixTest is Test, Addresses {

    using Address for *;
    using ERC20Lib for *;

    DolomiteMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;
    IDolomiteMargin internal dolomite;
    IERC20 internal isolationToken;
    IUnderlyingPositionFactory internal positionFactory;

    function setUp() public {
        vm.createSelectFork("arbitrum", 220_371_070);
        contango = _loadAddress("ContangoProxy");
        dolomite = IDolomiteMargin(_loadAddress("DolomiteMargin"));

        // Use latest code
        vm.etch(_loadAddress("DolomiteImmutableProxy"), address(new DolomiteMoneyMarket(Contango(contango), dolomite)).code);
    }

    function testLifeCycle_PositionIdAsAccountNumber() public {
        // setup
        positionFactory = Contango(contango).positionFactory();

        positionId = PositionId.wrap(0x5054654554484632345745544800000011ffffffff000000002a000000001302);
        sut = DolomiteMoneyMarket(address(positionFactory.moneyMarket(positionId)));
        Instrument memory instrument = Contango(contango).instrument(positionId.getSymbol());

        IERC20 lendToken = instrument.base;
        IERC20 borrowToken = instrument.quote;

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        _dealAndApprove(borrowToken, contango, debt / 4, address(sut));
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

        uint256 prevLent = sut.collateralBalance(positionId, lendToken);
        uint256 prevBorrow = sut.debtBalance(positionId, borrowToken);

        uint256 lendAmount = 0.1e18;
        uint256 borrowAmount = 0.01 ether;

        // lend
        _dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken),
            prevLent + lendAmount,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertEqDecimal(
            sut.debtBalance(positionId, borrowToken), prevBorrow + borrowAmount, borrowToken.decimals(), "debtBalance after lend + borrow"
        );
    }

    function testLifeCycle_CloneAddressAsAccountNumber() public {
        // setup
        positionFactory = Contango(contango).positionFactory();

        positionId = PositionId.wrap(0x5054657a45544846323457455448000011ffffffff0000000026000000001007);
        sut = DolomiteMoneyMarket(address(positionFactory.moneyMarket(positionId)));
        Instrument memory instrument = Contango(contango).instrument(positionId.getSymbol());

        IERC20 lendToken = instrument.base;
        IERC20 borrowToken = instrument.quote;

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        _dealAndApprove(borrowToken, contango, debt / 4, address(sut));
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

        uint256 prevLent = sut.collateralBalance(positionId, lendToken);
        uint256 prevBorrow = sut.debtBalance(positionId, borrowToken);

        uint256 lendAmount = 0.1e18;
        uint256 borrowAmount = 0.01 ether;

        // lend
        _dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertEqDecimal(lent, lendAmount, lendToken.decimals(), "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertEqDecimal(
            sut.collateralBalance(positionId, lendToken),
            prevLent + lendAmount,
            lendToken.decimals(),
            "collateralBalance after lend + borrow"
        );
        assertEqDecimal(
            sut.debtBalance(positionId, borrowToken), prevBorrow + borrowAmount, borrowToken.decimals(), "debtBalance after lend + borrow"
        );
    }

    function _dealAndApprove(IERC20 _token, address to, uint256 amount, address approveTo) internal virtual {
        deal(address(_token), to, amount);
        vm.prank(to);
        _token.approve(approveTo, amount);
    }

}

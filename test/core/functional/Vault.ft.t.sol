//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/core/Vault.sol";

import "../../BaseTest.sol";

contract VaultFunctional is BaseTest {

    Env internal env;
    IVault internal sut;
    IWETH9 internal weth;

    address internal depositor = makeAddr("Depositor");

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        weth = env.nativeToken();
        sut = new Vault(weth);
        Vault(payable(address(sut))).initialize(TIMELOCK);
    }

    function testDepositWithdraw(uint8 tokenIdx, uint128 depositAmount, uint256 preTransferAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && withdrawAmount > 0);

        IERC20 token = env.token(env.allTokens(bound(tokenIdx, 0, 3)));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setTokenSupport(token, true);

        preTransferAmount = preTransferAmount > depositAmount ? depositAmount : preTransferAmount;
        if (preTransferAmount > 0) deal(address(token), address(sut), preTransferAmount);
        env.dealAndApprove(token, depositor, depositAmount - preTransferAmount, address(sut));

        vm.prank(depositor);
        sut.deposit(token, depositor, depositAmount);

        assertEq(sut.balanceOf(token, depositor), depositAmount, "depositor balance");
        assertEq(sut.totalBalanceOf(token), depositAmount, "total balance");
        assertEq(token.balanceOf(address(sut)), depositAmount, "vault balance");
        assertEq(token.balanceOf(depositor), 0, "depositor token balance");

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(depositor);
        sut.withdraw(token, depositor, withdrawAmount, depositor);

        assertEq(sut.balanceOf(token, depositor), depositAmount - withdrawAmount, "depositor balance after withdraw");
        assertEq(sut.totalBalanceOf(token), depositAmount - withdrawAmount, "total balance after withdraw");
        assertEq(token.balanceOf(address(sut)), depositAmount - withdrawAmount, "vault balance after withdraw");
        assertEq(token.balanceOf(depositor), withdrawAmount, "depositor token balance after withdraw");
    }

    function testDepositToWithdraw(uint8 tokenIdx, uint128 depositAmount, uint256 preTransferAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && withdrawAmount > 0);

        IERC20 token = env.token(env.allTokens(bound(tokenIdx, 0, 3)));
        vm.prank(TIMELOCK_ADDRESS);
        sut.setTokenSupport(token, true);

        preTransferAmount = preTransferAmount > depositAmount ? depositAmount : preTransferAmount;
        if (preTransferAmount > 0) deal(address(token), address(sut), preTransferAmount);

        env.dealAndApprove(token, address(this), depositAmount - preTransferAmount, address(sut));
        sut.depositTo(token, depositor, depositAmount);

        assertEq(sut.balanceOf(token, depositor), depositAmount, "depositor balance");
        assertEq(sut.totalBalanceOf(token), depositAmount, "total balance");
        assertEq(token.balanceOf(address(sut)), depositAmount, "vault balance");
        assertEq(token.balanceOf(depositor), 0, "depositor token balance");

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(depositor);
        sut.withdraw(token, depositor, withdrawAmount, depositor);

        assertEq(sut.balanceOf(token, depositor), depositAmount - withdrawAmount, "depositor balance after withdraw");
        assertEq(sut.totalBalanceOf(token), depositAmount - withdrawAmount, "total balance after withdraw");
        assertEq(token.balanceOf(address(sut)), depositAmount - withdrawAmount, "vault balance after withdraw");
        assertEq(token.balanceOf(depositor), withdrawAmount, "depositor token balance after withdraw");
    }

    function testDepositWithdrawNative(uint128 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && withdrawAmount > 0);

        vm.deal(depositor, depositAmount);

        vm.prank(depositor);
        sut.depositNative{ value: depositAmount }(depositor);

        assertEq(sut.balanceOf(weth, depositor), depositAmount, "depositor balance");
        assertEq(sut.totalBalanceOf(weth), depositAmount, "total balance");
        assertEq(weth.balanceOf(address(sut)), depositAmount, "vault balance");
        assertEq(depositor.balance, 0, "depositor native balance");

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(depositor);
        sut.withdrawNative(depositor, withdrawAmount, depositor);

        assertEq(sut.balanceOf(weth, depositor), depositAmount - withdrawAmount, "depositor balance after withdraw");
        assertEq(sut.totalBalanceOf(weth), depositAmount - withdrawAmount, "total balance after withdraw");
        assertEq(weth.balanceOf(address(sut)), depositAmount - withdrawAmount, "vault balance after withdraw");
        assertEq(depositor.balance, withdrawAmount, "depositor native balance after withdraw");
    }

    function testValidations() public {
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.deposit(IERC20(address(0)), address(0), 0);
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.depositNative(address(0));
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.withdraw(IERC20(address(0)), address(0), 0, address(0));
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.withdrawNative(address(0), 0, address(0));

        vm.expectRevert(IVault.ZeroAmount.selector);
        vm.prank(depositor);
        sut.deposit(IERC20(address(0)), depositor, 0);

        vm.expectRevert(IVault.ZeroAmount.selector);
        vm.prank(depositor);
        sut.depositNative(depositor);

        vm.expectRevert(IVault.ZeroAmount.selector);
        vm.prank(depositor);
        sut.withdraw(IERC20(address(0)), depositor, 0, address(0));

        vm.expectRevert(IVault.ZeroAmount.selector);
        vm.prank(depositor);
        sut.withdrawNative(depositor, 0, address(0));

        vm.expectRevert(abi.encodeWithSelector(IVault.UnsupportedToken.selector, address(1)));
        vm.prank(depositor);
        sut.deposit(IERC20(address(1)), depositor, 1);
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "src/core/Vault.sol";

import "../../BaseTest.sol";

contract VaultFunctional is BaseTest, IVaultEvents {

    using { first } for Vm.Log[];

    Env internal env;
    Vault internal sut;
    IWETH9 internal weth;

    address internal depositor = makeAddr("Depositor");

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        weth = env.nativeToken();
        sut = new Vault(weth);
        Vault(payable(address(sut))).initialize(CORE_TIMELOCK);
        vm.prank(CORE_TIMELOCK_ADDRESS);
        sut.grantRole(OPERATOR_ROLE, CORE_TIMELOCK_ADDRESS);
    }

    function testDepositWithdraw(uint8 tokenIdx, uint128 depositAmount, uint256 preTransferAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && withdrawAmount > 0);

        IERC20 token = env.token(env.allTokens(bound(tokenIdx, 0, 3)));
        vm.prank(CORE_TIMELOCK_ADDRESS);
        sut.setTokenSupport(token, true);

        preTransferAmount = preTransferAmount > depositAmount ? depositAmount : preTransferAmount;
        if (preTransferAmount > 0) deal(address(token), address(sut), preTransferAmount);
        env.dealAndApprove(token, depositor, depositAmount - preTransferAmount, address(sut));

        vm.expectEmit(true, true, true, true);
        emit Deposited(token, depositor, depositAmount);

        vm.prank(depositor);
        uint256 deposited = sut.deposit(token, depositor, depositAmount);

        assertEq(deposited, depositAmount, "deposited amount");
        assertEq(sut.balanceOf(token, depositor), depositAmount, "depositor balance");
        assertEq(sut.totalBalanceOf(token), depositAmount, "total balance");
        assertEq(token.balanceOf(address(sut)), depositAmount, "vault balance");
        assertEq(token.balanceOf(depositor), 0, "depositor token balance");

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(token, depositor, withdrawAmount, depositor);

        vm.prank(depositor);
        uint256 withdrawn = sut.withdraw(token, depositor, withdrawAmount, depositor);

        assertEq(withdrawn, withdrawAmount, "withdrawn amount");
        assertEq(sut.balanceOf(token, depositor), depositAmount - withdrawAmount, "depositor balance after withdraw");
        assertEq(sut.totalBalanceOf(token), depositAmount - withdrawAmount, "total balance after withdraw");
        assertEq(token.balanceOf(address(sut)), depositAmount - withdrawAmount, "vault balance after withdraw");
        assertEq(token.balanceOf(depositor), withdrawAmount, "depositor token balance after withdraw");
    }

    function testDepositToWithdraw(uint8 tokenIdx, uint128 depositAmount, uint256 preTransferAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && withdrawAmount > 0);

        IERC20 token = env.token(env.allTokens(bound(tokenIdx, 0, 3)));
        vm.expectEmit(true, true, true, true);
        emit TokenSupportSet(token, true);
        vm.prank(CORE_TIMELOCK_ADDRESS);
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
        uint256 deposited = sut.depositNative{ value: depositAmount }(depositor);

        assertEq(deposited, depositAmount, "deposited amount");
        assertEq(sut.balanceOf(weth, depositor), depositAmount, "depositor balance");
        assertEq(sut.totalBalanceOf(weth), depositAmount, "total balance");
        assertEq(weth.balanceOf(address(sut)), depositAmount, "vault balance");
        assertEq(depositor.balance, 0, "depositor native balance");

        withdrawAmount = bound(withdrawAmount, 1, depositAmount);
        vm.prank(depositor);
        uint256 withdrawn = sut.withdrawNative(depositor, withdrawAmount, depositor);

        assertEq(withdrawn, withdrawAmount, "withdrawn amount");
        assertEq(sut.balanceOf(weth, depositor), depositAmount - withdrawAmount, "depositor balance after withdraw");
        assertEq(sut.totalBalanceOf(weth), depositAmount - withdrawAmount, "total balance after withdraw");
        assertEq(weth.balanceOf(address(sut)), depositAmount - withdrawAmount, "vault balance after withdraw");
        assertEq(depositor.balance, withdrawAmount, "depositor native balance after withdraw");
    }

    function testValidations() public {
        IERC20 token = IERC20(address(999));

        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.deposit(token, address(0), 0);
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.depositNative(address(0));
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.withdraw(token, address(0), 0, address(0));
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.withdrawNative(address(0), 0, address(0));
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.transfer(token, address(0), address(0), 0);

        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vm.prank(depositor);
        sut.deposit(token, depositor, 0);

        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vm.prank(depositor);
        sut.depositNative(depositor);

        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vm.prank(depositor);
        sut.withdraw(token, depositor, 0, address(0));

        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vm.prank(depositor);
        sut.withdrawNative(depositor, 0, address(0));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.UnsupportedToken.selector, token));
        vm.prank(depositor);
        sut.deposit(token, depositor, 1);

        vm.expectRevert(IVaultErrors.ZeroAmount.selector);
        vm.prank(depositor);
        sut.transfer(token, depositor, address(0), 0);

        vm.expectRevert(IVaultErrors.ZeroAddress.selector);
        vm.prank(depositor);
        sut.transfer(token, depositor, address(0), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NotEnoughBalance.selector, token, 0, 1));
        vm.prank(depositor);
        sut.transfer(token, depositor, address(1), 1);
    }

    function testDepositTransferWithdraw(uint8 tokenIdx, uint96 amount) public {
        vm.assume(amount > 0);

        IERC20 token = env.token(env.allTokens(bound(tokenIdx, 0, 3)));
        vm.prank(CORE_TIMELOCK_ADDRESS);
        sut.setTokenSupport(token, true);

        uint256 depositAmount = amount;
        env.dealAndApprove(token, depositor, depositAmount, address(sut));
        vm.prank(depositor);
        sut.deposit(token, depositor, depositAmount);

        uint256 transferAmount = bound(depositAmount, depositAmount / 3, depositAmount);
        address recipient = makeAddr("Recipient");

        vm.expectEmit(true, true, true, true);
        emit Transferred(token, depositor, recipient, transferAmount);

        vm.prank(depositor);
        uint256 transferred = sut.transfer(token, depositor, recipient, transferAmount);

        assertEq(transferred, transferAmount, "transferred amount");
        assertEq(sut.balanceOf(token, depositor), depositAmount - transferAmount, "depositor balance");
        assertEq(sut.balanceOf(token, recipient), transferAmount, "recipient balance");

        uint256 withdrawAmount = bound(transferAmount, transferAmount / 3, transferAmount);

        vm.prank(recipient);
        sut.withdraw(token, recipient, withdrawAmount, recipient);

        assertEq(sut.balanceOf(token, recipient), transferAmount - withdrawAmount, "recipient balance after withdraw");
        assertEq(token.balanceOf(recipient), withdrawAmount, "recipient token balance after withdraw");
    }

}

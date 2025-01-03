//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { TaxMan, Call, Result } from "src/utils/TaxMan.sol";

import "../BaseTest.sol";

contract TaxManTest is BaseTest {

    ERC20Mock internal token;

    TaxMan internal sut;

    function setUp() public {
        token = new ERC20Mock();

        sut = new TaxMan(TIMELOCK);
    }

    function _testCalls(bool success) internal view returns (Call[] memory testCalls) {
        testCalls = new Call[](1);
        testCalls[0] = Call({
            target: address(sut),
            value: 0,
            callData: success
                ? abi.encodeWithSelector(sut.assertBalanceGreaterOrEqualThan.selector, token, address(sut), 0)
                : abi.encodeWithSelector(sut.assertBalanceGreaterOrEqualThan.selector, token, address(sut), 1)
        });
    }

    function testPermissions() public {
        expectAccessControl(address(this), BOT_ROLE);
        sut.execute(_testCalls(true));

        expectAccessControl(address(this), EMERGENCY_BREAK_ROLE);
        sut.pause();

        expectAccessControl(address(this), RESTARTER_ROLE);
        sut.unpause();
    }

    function testExecute() public {
        VM.prank(TIMELOCK_ADDRESS);
        sut.grantRole(BOT_ROLE, BOT);

        VM.startPrank(BOT);

        // success
        Result[] memory results = sut.execute(_testCalls(true));
        assertTrue(results[0].success);

        // failure
        VM.expectRevert();
        sut.execute(_testCalls(false));

        VM.stopPrank();
    }

    function testAssertBalanceGreaterOrEqualThan(uint256 balance, bool equal) public {
        VM.assume(balance < type(uint256).max);
        VM.assume(balance > 0);
        token.mint(address(sut), balance);

        sut.assertBalanceGreaterOrEqualThan(token, address(sut), equal ? balance : balance - 1);

        uint256 balancePlusOne = balance + 1;

        VM.expectRevert(abi.encodeWithSelector(TaxMan.NotEnoughBalance.selector, token, balancePlusOne, balance));
        sut.assertBalanceGreaterOrEqualThan(token, address(sut), balancePlusOne);
    }

    function testPause() public {
        Call[] memory testCalls = _testCalls(true);

        VM.startPrank(TIMELOCK_ADDRESS);
        sut.grantRole(BOT_ROLE, BOT);
        sut.grantRole(EMERGENCY_BREAK_ROLE, address(this));
        sut.grantRole(RESTARTER_ROLE, address(this));
        VM.stopPrank();

        // pause
        sut.pause();

        VM.expectRevert("Pausable: paused");
        VM.prank(BOT);
        sut.execute(testCalls);

        // unpause
        sut.unpause();

        VM.prank(BOT);
        Result[] memory results = sut.execute(testCalls);
        assertTrue(results[0].success);
    }

}

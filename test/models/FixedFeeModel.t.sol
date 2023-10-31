//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "script/constants.sol";

import "../BaseTest.sol";
import "../TestSetup.t.sol";

import "src/libraries/DataTypes.sol";
import "src/models/FixedFeeModel.sol";

contract FixedFeeModelTest is BaseTest {

    using Math for *;

    FixedFeeModel private sut;

    function testAboveMaxFeeRevert(uint256 _fee) public {
        _fee = bound(_fee, MAX_FIXED_FEE + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(AboveMaxFee.selector, _fee));
        sut = new FixedFeeModel(TIMELOCK, _fee);
    }

    function testBelowMinFeeRevert(uint256 _fee) public {
        _fee = bound(_fee, 0, MIN_FIXED_FEE - 1);
        vm.expectRevert(abi.encodeWithSelector(BelowMinFee.selector, _fee));
        sut = new FixedFeeModel(TIMELOCK, _fee);
    }

    function testPermissions() public {
        sut = new FixedFeeModel(TIMELOCK, 0.001e18);

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.setFee(WETHUSDC, 0.001e18);

        expectAccessControl(address(this), DEFAULT_ADMIN_ROLE);
        sut.removeFee(WETHUSDC);
    }

    function testCalculateFees() public {
        // given
        PositionId positionId = encode(Symbol.wrap(""), MM_AAVE, PERP, 0, 0);
        uint256 feeRate = 0.0015e18;
        uint256 quantity = 10_000e18;
        uint256 expectedFees = 15e18;

        sut = new FixedFeeModel(TIMELOCK, feeRate);

        // when
        uint256 actualFees = sut.calculateFee(address(this), positionId, quantity);

        // then
        assertEq(expectedFees, actualFees);
    }

    function testCalculateFeesPerSymbol() public {
        // given
        PositionId positionId = encode(WETHUSDC, MM_AAVE, PERP, 0, 0);
        uint256 defaultFeeRate = 0.0015e18;
        uint256 quantity = 100e18;
        uint256 expectedDefaultFees = 0.15e18;

        sut = new FixedFeeModel(TIMELOCK, defaultFeeRate);

        // when
        uint256 symbolFeeRate = 0.0001e18;
        uint256 expectedSymbolFees = 0.01e18;

        vm.prank(TIMELOCK_ADDRESS);
        sut.setFee(WETHUSDC, symbolFeeRate);

        uint256 actualSymbolFees = sut.calculateFee(address(this), positionId, quantity);

        vm.prank(TIMELOCK_ADDRESS);
        sut.setFee(WETHUSDC, NO_FEE);
        uint256 actualNoFees = sut.calculateFee(address(this), positionId, quantity);

        vm.prank(TIMELOCK_ADDRESS);
        sut.removeFee(WETHUSDC);
        uint256 revertedFees = sut.calculateFee(address(this), positionId, quantity);

        // then
        assertEq(expectedSymbolFees, actualSymbolFees, "actualSymbolFees");
        assertEq(0, actualNoFees, "actualNoFees");
        assertEq(expectedDefaultFees, revertedFees, "revertedFees");
    }

    function testCalculateFees6Decimals() public {
        // given
        PositionId positionId = encode(Symbol.wrap(""), MM_AAVE, PERP, 0, 0);
        uint256 feeRate = 0.0015e18;
        uint256 quantity = 10_000e6;
        uint256 expectedFees = 15e6;

        sut = new FixedFeeModel(TIMELOCK, feeRate);

        // when
        uint256 actualFees = sut.calculateFee(address(this), positionId, quantity);

        // then
        assertEq(expectedFees, actualFees);
    }

    function testCalculateFeeFuzzInput(
        uint256 defaultFeeRate,
        uint256 symbolFeeRate,
        address trader,
        PositionId positionId,
        uint128 quantity
    ) public {
        defaultFeeRate = bound(defaultFeeRate, MIN_FIXED_FEE, MAX_FIXED_FEE);
        symbolFeeRate = bound(symbolFeeRate, MIN_FIXED_FEE, MAX_FIXED_FEE);

        // given
        vm.assume(quantity != 0);
        vm.assume(defaultFeeRate != symbolFeeRate);

        sut = new FixedFeeModel(TIMELOCK, defaultFeeRate);

        uint256 expectedDefaultFees = uint256(quantity).mulDiv(defaultFeeRate, 1e18, Math.Rounding.Up);
        uint256 expectedSymbolFees = uint256(quantity).mulDiv(symbolFeeRate, 1e18, Math.Rounding.Up);

        // when
        uint256 actualDefaultFees = sut.calculateFee(trader, positionId, quantity);

        vm.prank(TIMELOCK_ADDRESS);
        sut.setFee(positionId.getSymbol(), symbolFeeRate);
        uint256 actualSymbolFees = sut.calculateFee(trader, positionId, quantity);

        vm.prank(TIMELOCK_ADDRESS);
        sut.removeFee(positionId.getSymbol());
        uint256 removedSymbolFees = sut.calculateFee(trader, positionId, quantity);

        // then
        assertEq(expectedDefaultFees, actualDefaultFees, "actualDefaultFees");
        assertEq(expectedSymbolFees, actualSymbolFees, "actualSymbolFees");
        assertEq(removedSymbolFees, actualDefaultFees, "removedSymbolFees");
    }

}

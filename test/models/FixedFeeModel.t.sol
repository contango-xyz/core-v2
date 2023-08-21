//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "script/constants.sol";

import "../TestSetup.t.sol";
import "src/libraries/DataTypes.sol";
import "src/models/FixedFeeModel.sol";

contract FixedFeeModelTest is Test {

    using Math for *;

    FixedFeeModel private sut;

    function testAboveMaxFeeRevert(uint256 _fee) public {
        _fee = bound(_fee, MAX_FIXED_FEE + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(AboveMaxFee.selector, _fee));
        sut = new FixedFeeModel(_fee);
    }

    function testBelowMinFeeRevert(uint256 _fee) public {
        _fee = bound(_fee, 0, MIN_FIXED_FEE - 1);
        vm.expectRevert(abi.encodeWithSelector(BelowMinFee.selector, _fee));
        sut = new FixedFeeModel(_fee);
    }

    function testCalculateFees() public {
        // given
        PositionId positionId = encode(Symbol.wrap(""), MM_AAVE, PERP, 0, 0);
        uint256 feeRate = 0.0015e18;
        uint256 quantity = 10_000e18;
        uint256 expectedFees = 15e18;

        sut = new FixedFeeModel(feeRate);

        // when
        uint256 actualFees = sut.calculateFee(address(this), positionId, quantity);

        // then
        assertEq(expectedFees, actualFees);
    }

    function testCalculateFees6Decimals() public {
        // given
        PositionId positionId = encode(Symbol.wrap(""), MM_AAVE, PERP, 0, 0);
        uint256 feeRate = 0.0015e18;
        uint256 quantity = 10_000e6;
        uint256 expectedFees = 15e6;

        sut = new FixedFeeModel(feeRate);

        // when
        uint256 actualFees = sut.calculateFee(address(this), positionId, quantity);

        // then
        assertEq(expectedFees, actualFees);
    }

    function testCalculateFeeFuzzInput(uint256 feeRate, address trader, PositionId positionId, uint128 quantity) public {
        feeRate = bound(feeRate, MIN_FIXED_FEE, MAX_FIXED_FEE);

        // given
        vm.assume(quantity != 0);

        sut = new FixedFeeModel(feeRate);

        uint256 expectedFees = uint256(quantity).mulDiv(feeRate, 1e18, Math.Rounding.Up);

        // when
        uint256 actualFees = sut.calculateFee(trader, positionId, quantity);

        // then
        assertEq(expectedFees, actualFees);
    }

}

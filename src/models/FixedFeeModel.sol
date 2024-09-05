//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/IFeeModel.sol";

uint256 constant MAX_FIXED_FEE = WAD; // 100%
uint256 constant MIN_FIXED_FEE = 0.000001e18; // 0.0001%
uint256 constant NO_FEE = type(uint256).max;

error AboveMaxFee(uint256 fee);
error BelowMinFee(uint256 fee);

contract FixedFeeModel is IFeeModel, AccessControl {

    using Math for *;

    event DefaultFeeSet(uint256 fee);
    event FeeSet(Symbol indexed symbol, uint256 fee);
    event FeeRemoved(Symbol indexed symbol);

    mapping(Symbol symbol => uint256 fee) public symbolFee;
    uint256 public defaultFee = NO_FEE; // fee percentage in wad, e.g. 0.0015e18 -> 0.15%

    constructor(Timelock timelock) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    /// @inheritdoc IFeeModel
    function calculateFee(address, PositionId positionId, uint256 quantity) external view override returns (uint256 calculatedFee) {
        uint256 fee = symbolFee[positionId.getSymbol()];
        fee = fee > 0 ? fee : defaultFee;

        if (fee != NO_FEE) calculatedFee = quantity.mulDiv(fee, WAD, Math.Rounding.Up);
    }

    function setDefaultFee(uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        defaultFee = fee == NO_FEE ? fee : _validateFee(fee);
        emit DefaultFeeSet(fee);
    }

    function setFee(Symbol symbol, uint256 fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        symbolFee[symbol] = fee == NO_FEE ? fee : _validateFee(fee);
        emit FeeSet(symbol, fee);
    }

    function removeFee(Symbol symbol) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delete symbolFee[symbol];
        emit FeeRemoved(symbol);
    }

    function _validateFee(uint256 fee) private pure returns (uint256) {
        if (fee > MAX_FIXED_FEE) revert AboveMaxFee(fee);
        if (fee < MIN_FIXED_FEE) revert BelowMinFee(fee);
        return fee;
    }

}

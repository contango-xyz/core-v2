//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./CompoundMoneyMarket.sol";

contract LodestarMoneyMarket is CompoundMoneyMarket {

    using ERC20Lib for IERC20;

    IERC20 public immutable arbToken;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        CompoundReverseLookup _reverseLookup,
        IWETH9 _nativeToken,
        IERC20 _arbToken
    ) CompoundMoneyMarket(_moneyMarketId, _contango, _reverseLookup, _nativeToken) {
        arbToken = _arbToken;
    }

    function _claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal override {
        super._claimRewards(positionId, collateralAsset, debtAsset, to);
        arbToken.transferBalance(to);
    }

}

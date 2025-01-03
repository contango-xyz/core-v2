//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IUnderlyingPositionFactory.sol";
import { Timelock, PositionId } from "../libraries/DataTypes.sol";
import { CONTANGO_ROLE } from "../libraries/Roles.sol";

contract UnderlyingPositionFactory is IUnderlyingPositionFactory, AccessControl {

    error InvalidMoneyMarket(MoneyMarketId mm);
    error MoneyMarketAlreadyRegistered(MoneyMarketId mm, IMoneyMarket imm);

    struct MoneyMarketData {
        IMoneyMarket moneyMarket;
        bool needsAccount;
    }

    mapping(MoneyMarketId moneyMarketId => MoneyMarketData mmData) public moneyMarkets;

    constructor(Timelock timelock) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function registerMoneyMarket(IMoneyMarket imm) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        MoneyMarketId mm = imm.moneyMarketId();
        if (moneyMarkets[mm].moneyMarket != IMoneyMarket(address(0))) revert MoneyMarketAlreadyRegistered(mm, imm);

        moneyMarkets[mm] = MoneyMarketData({ moneyMarket: imm, needsAccount: imm.NEEDS_ACCOUNT() });
        emit MoneyMarketRegistered(mm, imm);
    }

    function createUnderlyingPosition(PositionId positionId) external override onlyRole(CONTANGO_ROLE) returns (IMoneyMarket imm) {
        MoneyMarketId mm = positionId.getMoneyMarket();
        MoneyMarketData memory mmData = _moneyMarket(mm);
        imm = mmData.moneyMarket;

        if (mmData.needsAccount) {
            imm = IMoneyMarket(Clones.cloneDeterministic(address(imm), PositionId.unwrap(positionId)));
            emit UnderlyingPositionCreated(address(imm), positionId);
        }
    }

    function moneyMarket(PositionId positionId) external view override returns (IMoneyMarket imm) {
        MoneyMarketId mm = positionId.getMoneyMarket();
        MoneyMarketData memory mmData = _moneyMarket(mm);
        imm = mmData.moneyMarket;

        if (mmData.needsAccount) imm = IMoneyMarket(Clones.predictDeterministicAddress(address(imm), PositionId.unwrap(positionId)));
    }

    function moneyMarket(MoneyMarketId mm) public view override returns (IMoneyMarket) {
        return _moneyMarket(mm).moneyMarket;
    }

    function _moneyMarket(MoneyMarketId mm) private view returns (MoneyMarketData memory mmData) {
        mmData = moneyMarkets[mm];
        if (address(mmData.moneyMarket) == address(0)) revert InvalidMoneyMarket(mm);
    }

}

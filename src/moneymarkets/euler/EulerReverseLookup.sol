//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import { OPERATOR_ROLE } from "../../libraries/Roles.sol";
import { Timelock, PositionId, Payload } from "../../libraries/DataTypes.sol";
import "./dependencies/IEulerVault.sol";

interface EulerReverseLookupEvents {

    event VaultSet(uint16 indexed id, IEulerVault indexed vault);

}

contract EulerReverseLookup is EulerReverseLookupEvents, AccessControl {

    error VaultNotFound(uint16 id);
    error VaultAlreadySet(uint16 id);

    uint16 public nextId = 1;
    mapping(uint16 id => IEulerVault vault) public idToVault;
    mapping(IEulerVault vault => uint16 id) public vaultToId;

    constructor(Timelock timelock) {
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _grantRole(OPERATOR_ROLE, Timelock.unwrap(timelock));
    }

    function setVault(IEulerVault _vault) external onlyRole(OPERATOR_ROLE) returns (uint16 id) {
        require(vaultToId[_vault] == 0, VaultAlreadySet(vaultToId[_vault]));

        id = nextId++;
        idToVault[id] = _vault;
        vaultToId[_vault] = id;

        emit VaultSet(id, _vault);
    }

    function vault(uint16 id) public view returns (IEulerVault _vault) {
        _vault = idToVault[id];
        require(_vault != IEulerVault(address(0)), VaultNotFound(id));
    }

    function base(PositionId positionId) external view returns (IEulerVault) {
        (uint16 baseId,) = _splitBytes(positionId.getPayload());
        return vault(baseId);
    }

    function quote(PositionId positionId) external view returns (IEulerVault) {
        (, uint16 quoteId) = _splitBytes(positionId.getPayload());
        return vault(quoteId);
    }

    function _splitBytes(Payload p) internal pure returns (uint16 baseId, uint16 quoteId) {
        bytes5 b = Payload.unwrap(p);
        baseId = uint16(bytes2(b << 8));
        quoteId = uint16(bytes2(b << 24));
    }

}

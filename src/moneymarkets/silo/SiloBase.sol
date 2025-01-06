//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./dependencies/Silo.sol";
import { isBitSet } from "../../libraries/BitFlags.sol";
import { PositionId } from "../../libraries/DataTypes.sol";

uint256 constant COLLATERAL_ONLY = 0;

abstract contract SiloBase {

    ISiloLens public immutable lens;
    ISilo public immutable wstEthSilo;
    IERC20 public immutable weth;
    IERC20 public immutable stablecoin;
    ISiloRepository public immutable repository;

    constructor(ISiloLens _lens, ISilo _wstEthSilo, IERC20 _weth, IERC20 _stablecoin) {
        lens = _lens;
        wstEthSilo = _wstEthSilo;
        weth = _weth;
        stablecoin = _stablecoin;
        repository = _lens.siloRepository();
    }

    function getSilo(IERC20 collateralAsset, IERC20 debtAsset) public view returns (ISilo silo_) {
        if (collateralAsset == weth && debtAsset == stablecoin || collateralAsset == stablecoin && debtAsset == weth) return wstEthSilo;
        silo_ = repository.getSilo(collateralAsset);
        if (address(silo_) == address(0)) silo_ = repository.getSilo(debtAsset);
    }

}

function isCollateralOnly(PositionId positionId) pure returns (bool) {
    return isBitSet(positionId.getFlags(), COLLATERAL_ONLY);
}

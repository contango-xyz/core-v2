//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./dependencies/Silo.sol";

abstract contract SiloBase {

    ISiloLens public constant LENS = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
    ISiloIncentivesController public constant INCENTIVES_CONTROLLER = ISiloIncentivesController(0xd592F705bDC8C1B439Bd4D665Ed99C4FaAd5A680);
    ISilo public constant WSTETH_SILO = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    ISiloRepository public immutable repository = LENS.siloRepository();

    function getSilo(IERC20 collateralAsset, IERC20 debtAsset) public view returns (ISilo silo_) {
        if (collateralAsset == WETH && debtAsset == USDC || collateralAsset == USDC && debtAsset == WETH) return WSTETH_SILO;
        silo_ = repository.getSilo(collateralAsset);
        if (address(silo_) == address(0)) silo_ = repository.getSilo(debtAsset);
    }

}

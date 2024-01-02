//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./Silo.sol";
import "../BaseMoneyMarket.sol";
import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";
import { MM_SILO } from "script/constants.sol";

contract SiloMoneyMarket is BaseMoneyMarket {

    using SafeERC20 for *;
    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;
    bool public constant COLLATERAL_ONLY = false;
    ISiloLens public constant LENS = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
    ISiloIncentivesController public constant INCENTIVES_CONTROLLER = ISiloIncentivesController(0xd592F705bDC8C1B439Bd4D665Ed99C4FaAd5A680);
    ISilo public constant WSTETH_SILO = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    ISiloRepository public immutable repository = LENS.siloRepository();

    ISilo public silo;

    constructor(IContango _contango) BaseMoneyMarket(MM_SILO, _contango) { }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        silo = (collateralAsset == WETH || collateralAsset == USDC) ? WSTETH_SILO : repository.getSilo(collateralAsset);
        collateralAsset.forceApprove(address(silo), type(uint256).max);
        debtAsset.forceApprove(address(silo), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal virtual override returns (uint256 balance) {
        silo.accrueInterest(asset);
        balance = LENS.collateralBalanceOfUnderlying(silo, asset, address(this));
    }

    function _lend(PositionId, IERC20 asset, uint256 amount, address payer) internal virtual override returns (uint256 actualAmount) {
        (actualAmount,) = silo.deposit(asset, asset.transferOut(payer, address(this), amount), COLLATERAL_ONLY);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to) internal virtual override returns (uint256 actualAmount) {
        (actualAmount,) = silo.borrow(asset, amount);
        asset.transferOut(address(this), to, actualAmount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer) internal virtual override returns (uint256 actualAmount) {
        (actualAmount,) = silo.repay(asset, asset.transferOut(payer, address(this), amount));
        if (actualAmount < amount) asset.transferOut(address(this), payer, amount - actualAmount);
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        if (amount == _collateralBalance(positionId, asset)) amount = type(uint256).max;
        (actualAmount,) = silo.withdraw(asset, amount, COLLATERAL_ONLY);
        asset.transferOut(address(this), to, actualAmount);
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        INCENTIVES_CONTROLLER.claimRewards(
            toArray(silo.assetStorage(collateralAsset).collateralToken, silo.assetStorage(debtAsset).debtToken), type(uint256).max, to
        );
    }

}

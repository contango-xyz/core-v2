//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "@aave/core-v3/contracts/flashloan/base/FlashLoanReceiverBase.sol";
import "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import "./dependencies/IAaveRewardsController.sol";

import "../BaseMoneyMarket.sol";
import "../interfaces/IFlashBorrowProvider.sol";
import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";
import { isBitSet } from "../../libraries/BitFlags.sol";

uint256 constant E_MODE = 0;
uint256 constant ISOLATION_MODE = 1;

contract AaveMoneyMarket is BaseMoneyMarket, FlashLoanReceiverBase, IFlashBorrowProvider {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using SafeERC20 for *;
    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;

    MoneyMarket public immutable override moneyMarketId;
    IAaveRewardsController public immutable rewardsController;

    constructor(
        MoneyMarket _moneyMarketId,
        IContango _contango,
        IPoolAddressesProvider _provider,
        IAaveRewardsController _rewardsController
    ) BaseMoneyMarket(_contango) FlashLoanReceiverBase(_provider) {
        moneyMarketId = _moneyMarketId;
        rewardsController = _rewardsController;
    }

    // ====== IMoneyMarket =======

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        if (isBitSet(positionId.getFlags(), E_MODE)) {
            POOL.setUserEMode(uint8(POOL.getReserveData(address(collateralAsset)).configuration.getEModeCategory()));
        }

        collateralAsset.forceApprove(address(POOL), type(uint256).max);
        debtAsset.forceApprove(address(POOL), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view override returns (uint256 balance) {
        return IERC20(POOL.getReserveData(address(asset)).aTokenAddress).balanceOf(address(this));
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        actualAmount = asset.transferOut(payer, address(this), amount);
        POOL.supply({ asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0 });
        if (isBitSet(positionId.getFlags(), ISOLATION_MODE)) POOL.setUserUseReserveAsCollateral(address(asset), true);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        POOL.borrow({
            asset: address(asset),
            amount: amount,
            interestRateMode: uint8(DataTypes.InterestRateMode.VARIABLE),
            onBehalfOf: address(this),
            referralCode: 0
        });

        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer) internal override returns (uint256 actualAmount) {
        actualAmount = Math.min(amount, IERC20(POOL.getReserveData(address(asset)).variableDebtTokenAddress).balanceOf(address(this)));
        if (actualAmount > 0) {
            asset.transferOut(payer, address(this), actualAmount);
            actualAmount = POOL.repay({
                asset: address(asset),
                amount: actualAmount,
                interestRateMode: uint8(DataTypes.InterestRateMode.VARIABLE),
                onBehalfOf: address(this)
            });
        }
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to) internal override returns (uint256 actualAmount) {
        actualAmount = POOL.withdraw({ asset: address(asset), amount: amount, to: to });
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal override {
        rewardsController.claimAllRewards(
            toArray(
                POOL.getReserveData(address(collateralAsset)).aTokenAddress,
                POOL.getReserveData(address(debtAsset)).variableDebtTokenAddress
            ),
            to
        );
    }

    // ===== IFlashBorrowProvider =====

    struct MetaParams {
        bytes params;
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback;
    }

    bytes internal tmpResult;

    function flashBorrow(
        IERC20 asset,
        uint256 amount,
        bytes calldata params,
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback
    ) public override onlyContango returns (bytes memory result) {
        POOL.flashLoan({
            receiverAddress: address(this),
            assets: toArray(address(asset)),
            amounts: toArray(amount),
            interestRateModes: toArray(uint8(DataTypes.InterestRateMode.VARIABLE)),
            onBehalfOf: address(this),
            params: abi.encode(MetaParams({ params: params, callback: callback })),
            referralCode: 0
        });

        result = tmpResult;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (msg.sender != address(POOL) || initiator != address(this)) revert InvalidSenderOrInitiator();

        MetaParams memory metaParams = abi.decode(params, (MetaParams));

        IERC20(assets[0]).safeTransfer(metaParams.callback.address, amounts[0]);

        tmpResult = metaParams.callback(IERC20(assets[0]), amounts[0], metaParams.params);

        return true;
    }

    function supportsInterface(bytes4 interfaceId) public pure override(BaseMoneyMarket, IERC165) returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId || interfaceId == type(IFlashBorrowProvider).interfaceId;
    }

}

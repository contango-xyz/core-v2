//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IPool.sol";
import "./dependencies/IFlashLoanReceiver.sol";
import "./dependencies/IAaveRewardsController.sol";
import "./dependencies/IPoolDataProvider.sol";
import "./dependencies/AaveDataTypes.sol";

import "../BaseMoneyMarket.sol";
import "../interfaces/IFlashBorrowProvider.sol";
import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";
import { isBitSet } from "../../libraries/BitFlags.sol";

uint256 constant E_MODE = 0;
uint256 constant ISOLATION_MODE = 1;

contract AaveMoneyMarket is BaseMoneyMarket, IFlashLoanReceiver, IFlashBorrowProvider {

    using SafeERC20 for *;
    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;

    IPool public immutable pool;
    IPoolDataProvider public immutable dataProvider;
    IAaveRewardsController public immutable rewardsController;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveRewardsController _rewardsController
    ) BaseMoneyMarket(_moneyMarketId, _contango) {
        pool = _pool;
        dataProvider = _dataProvider;
        rewardsController = _rewardsController;
    }

    // ====== IMoneyMarket =======

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        if (!positionId.isPerp()) revert InvalidExpiry();

        if (isBitSet(positionId.getFlags(), E_MODE)) {
            pool.setUserEMode(uint8(dataProvider.getReserveEModeCategory(address(collateralAsset))));
        }

        collateralAsset.forceApprove(address(pool), type(uint256).max);
        debtAsset.forceApprove(address(pool), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view virtual override returns (uint256 balance) {
        return _aToken(asset).balanceOf(address(this));
    }

    function debtBalance(PositionId, IERC20 asset) public view virtual returns (uint256 balance) {
        return _vToken(asset).balanceOf(address(this));
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = asset.transferOut(payer, address(this), amount);
        _supply(asset, amount);
        if (isBitSet(positionId.getFlags(), ISOLATION_MODE)) pool.setUserUseReserveAsCollateral(address(asset), true);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to) internal virtual override returns (uint256 actualAmount) {
        pool.borrow({
            asset: address(asset),
            amount: amount,
            interestRateMode: uint8(AaveDataTypes.InterestRateMode.VARIABLE),
            onBehalfOf: address(this),
            referralCode: 0
        });

        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, debtBalance(positionId, asset));
        if (actualAmount > 0) {
            asset.transferOut(payer, address(this), actualAmount);
            actualAmount = pool.repay({
                asset: address(asset),
                amount: actualAmount,
                interestRateMode: uint8(AaveDataTypes.InterestRateMode.VARIABLE),
                onBehalfOf: address(this)
            });
        }
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to) internal virtual override returns (uint256 actualAmount) {
        actualAmount = pool.withdraw({ asset: address(asset), amount: amount, to: to });
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        rewardsController.claimAllRewards(toArray(_aToken(collateralAsset), _vToken(debtAsset)), to);
    }

    function _aToken(IERC20 asset) internal view virtual returns (IERC20 aToken) {
        aToken = IERC20(pool.getReserveData(address(asset)).aTokenAddress);
    }

    function _vToken(IERC20 asset) internal view virtual returns (IERC20 vToken) {
        vToken = IERC20(pool.getReserveData(address(asset)).variableDebtTokenAddress);
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
    ) public virtual override returns (bytes memory result) {
        return _flashBorrow(asset, amount, abi.encode(MetaParams({ params: params, callback: callback })));
    }

    function _flashBorrow(IERC20 asset, uint256 amount, bytes memory metaParams) internal onlyContango returns (bytes memory result) {
        pool.flashLoan({
            receiverAddress: address(this),
            assets: toArray(address(asset)),
            amounts: toArray(amount),
            interestRateModes: toArray(uint8(AaveDataTypes.InterestRateMode.VARIABLE)),
            onBehalfOf: address(this),
            params: metaParams,
            referralCode: 0
        });

        result = tmpResult;
        delete tmpResult;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address initiator,
        bytes calldata metaParams
    ) public override returns (bool) {
        if (msg.sender != address(pool) || initiator != address(this)) revert InvalidSenderOrInitiator();

        (
            IERC20 asset,
            uint256 amount,
            function(IERC20, uint256, bytes memory) external returns (bytes memory) callback,
            bytes memory params
        ) = _handleMetaParams(assets, amounts, metaParams);

        asset.safeTransfer(callback.address, amount);

        tmpResult = callback(asset, amount, params);

        return true;
    }

    function _handleMetaParams(address[] calldata assets, uint256[] calldata amounts, bytes memory metaParamsBytes)
        internal
        virtual
        returns (
            IERC20 asset,
            uint256 amount,
            function(IERC20, uint256, bytes memory) external returns (bytes memory) callback,
            bytes memory params
        )
    {
        MetaParams memory metaParams = abi.decode(metaParamsBytes, (MetaParams));
        asset = IERC20(assets[0]);
        amount = amounts[0];
        callback = metaParams.callback;
        params = metaParams.params;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId || interfaceId == type(IFlashBorrowProvider).interfaceId;
    }

    function _supply(IERC20 asset, uint256 amount) internal virtual {
        pool.supply({ asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0 });
    }

}

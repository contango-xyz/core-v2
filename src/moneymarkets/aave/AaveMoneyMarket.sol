//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IPoolAddressesProvider.sol";
import "./dependencies/IFlashLoanReceiver.sol";
import "./dependencies/IAaveRewardsController.sol";
import "./dependencies/AaveDataTypes.sol";

import "../BaseMoneyMarket.sol";
import "../interfaces/IFlashBorrowProvider.sol";
import "../../libraries/ERC20Lib.sol";
import { toArray } from "../../libraries/Arrays.sol";
import { isBitSet } from "../../libraries/BitFlags.sol";

uint256 constant E_MODE = 0;
uint256 constant ISOLATION_MODE = 1;

contract AaveMoneyMarket is BaseMoneyMarket, IFlashLoanReceiver, IFlashBorrowProvider {

    using SafeERC20 for *;
    using ERC20Lib for *;

    bool public constant override NEEDS_ACCOUNT = true;

    IPoolAddressesProvider public immutable poolAddressesProvider;
    IAaveRewardsController public immutable rewardsController;
    bool public immutable flashBorrowEnabled;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IPoolAddressesProvider _poolAddressesProvider,
        IAaveRewardsController _rewardsController,
        bool _flashBorrowEnabled
    ) BaseMoneyMarket(_moneyMarketId, _contango) {
        poolAddressesProvider = _poolAddressesProvider;
        rewardsController = _rewardsController;
        flashBorrowEnabled = _flashBorrowEnabled;
    }

    // ====== IMoneyMarket =======

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual override {
        require(positionId.isPerp(), InvalidExpiry());

        IPool _pool = pool();
        if (isBitSet(positionId.getFlags(), E_MODE)) _pool.setUserEMode(uint8(uint32(positionId.getPayloadNoFlags())));

        collateralAsset.forceApprove(address(_pool), type(uint256).max);
        debtAsset.forceApprove(address(_pool), type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20 asset) internal view virtual override returns (uint256 balance) {
        return _aToken(asset).balanceOf(address(this));
    }

    function _debtBalance(PositionId, IERC20 asset) internal view virtual override returns (uint256 balance) {
        return _vToken(asset).balanceOf(address(this));
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = asset.transferOut(payer, address(this), amount);
        _supply(asset, amount);
        if (isBitSet(positionId.getFlags(), ISOLATION_MODE)) pool().setUserUseReserveAsCollateral(address(asset), true);
    }

    function _borrow(PositionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        pool().borrow({
            asset: address(asset),
            amount: amount,
            interestRateMode: uint8(AaveDataTypes.InterestRateMode.VARIABLE),
            onBehalfOf: address(this),
            referralCode: 0
        });

        actualAmount = asset.transferOut(address(this), to, amount);
    }

    function _repay(PositionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = Math.min(amount, debt);
        if (actualAmount > 0) {
            asset.transferOut(payer, address(this), actualAmount);
            actualAmount = pool().repay({
                asset: address(asset),
                amount: actualAmount,
                interestRateMode: uint8(AaveDataTypes.InterestRateMode.VARIABLE),
                onBehalfOf: address(this)
            });
        }
    }

    function _withdraw(PositionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        virtual
        override
        returns (uint256 actualAmount)
    {
        actualAmount = pool().withdraw({ asset: address(asset), amount: amount, to: to });
    }

    function _claimRewards(PositionId, IERC20 collateralAsset, IERC20 debtAsset, address to) internal virtual override {
        rewardsController.claimAllRewards(toArray(_aToken(collateralAsset), _vToken(debtAsset)), to);
    }

    function _aToken(IERC20 asset) internal view virtual returns (IERC20 aToken) {
        aToken = IERC20(pool().getReserveData(asset).aTokenAddress);
    }

    function _vToken(IERC20 asset) internal view virtual returns (IERC20 vToken) {
        vToken = IERC20(pool().getReserveData(asset).variableDebtTokenAddress);
    }

    // ===== IFlashBorrowProvider =====

    struct MetaParams {
        bytes params;
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback;
    }

    bytes internal tmpResult;

    function flashBorrow(
        PositionId positionId,
        IERC20 asset,
        uint256 amount,
        bytes calldata params,
        function(IERC20, uint256, bytes memory) external returns (bytes memory) callback
    ) public virtual override returns (bytes memory result) {
        require(flashBorrowEnabled, UnsupportedOperation());
        return _flashBorrow(positionId, asset, amount, abi.encode(MetaParams({ params: params, callback: callback })));
    }

    function _flashBorrow(PositionId positionId, IERC20 asset, uint256 amount, bytes memory metaParams)
        internal
        onlyContango
        returns (bytes memory result)
    {
        uint256 balanceBefore = _debtBalance(positionId, asset);
        pool().flashLoan({
            receiverAddress: address(this),
            assets: toArray(address(asset)),
            amounts: toArray(amount),
            interestRateModes: toArray(uint8(AaveDataTypes.InterestRateMode.VARIABLE)),
            onBehalfOf: address(this),
            params: metaParams,
            referralCode: 0
        });

        emit Borrowed(positionId, asset, amount, balanceBefore);

        result = tmpResult;
        delete tmpResult;
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address initiator,
        bytes calldata metaParams
    ) public virtual override returns (bool) {
        require(flashBorrowEnabled, UnsupportedOperation());
        if (msg.sender != address(pool()) || initiator != address(this)) revert InvalidSenderOrInitiator();

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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IMoneyMarket).interfaceId || (flashBorrowEnabled && interfaceId == type(IFlashBorrowProvider).interfaceId);
    }

    function _supply(IERC20 asset, uint256 amount) internal virtual {
        pool().supply({ asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0 });
    }

    function pool() public view virtual returns (IPool) {
        return poolAddressesProvider.getPool();
    }

}

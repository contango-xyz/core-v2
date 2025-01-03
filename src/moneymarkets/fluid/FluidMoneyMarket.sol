//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";

import { MM_FLUID } from "script/constants.sol";

import "../../libraries/ERC20Lib.sol";

import "../BaseMoneyMarket.sol";

import "./dependencies/IFluidVaultResolver.sol";

contract FluidMoneyMarket is BaseMoneyMarket {

    bytes32 public constant NFT_ID_SLOT = keccak256("FluidMoneyMarket.nftId");

    using ERC20Lib for *;
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using StorageSlot for bytes32;

    bool public constant override NEEDS_ACCOUNT = true;

    IWETH9 public immutable nativeToken;
    IFluidVaultResolver public immutable resolver;

    constructor(IContango _contango, IWETH9 _nativeToken, IFluidVaultResolver _resolver) BaseMoneyMarket(MM_FLUID, _contango) {
        nativeToken = _nativeToken;
        resolver = _resolver;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override {
        require(positionId.isPerp(), InvalidExpiry());

        address vaultAddr = address(vault(positionId));
        collateralAsset.forceApprove(vaultAddr, type(uint256).max);
        debtAsset.forceApprove(vaultAddr, type(uint256).max);
    }

    function _collateralBalance(PositionId, IERC20) internal view override returns (uint256 balance) {
        (IFluidVaultResolver.UserPosition memory userPosition,) = resolver.positionByNftId(nftId());
        balance = userPosition.supply;
    }

    function _debtBalance(PositionId, IERC20) internal view override returns (uint256 balance) {
        (IFluidVaultResolver.UserPosition memory userPosition,) = resolver.positionByNftId(nftId());
        balance = userPosition.borrow;
    }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        asset.transferOut(payer, address(this), amount);

        uint256 value;
        if (asset == nativeToken) nativeToken.withdraw(value = amount);

        uint256 _nftId = nftId();
        (uint256 nftId_, int256 lent,) = vault(positionId).operate{ value: value }(_nftId, amount.toInt256(), 0, address(0));
        if (_nftId == 0) nftId(nftId_);

        actualAmount = lent.toUint256();
    }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    {
        bool isNative = asset == nativeToken;

        (,, int256 borrowed) = vault(positionId).operate(nftId(), 0, amount.toInt256(), isNative ? address(this) : to);
        actualAmount = borrowed.toUint256();

        if (isNative) nativeToken.transferOut(address(this), to, actualAmount);
    }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256 debt)
        internal
        override
        returns (uint256 actualAmount)
    {
        asset.transferOut(payer, address(this), amount);

        uint256 value;
        if (asset == nativeToken) nativeToken.withdraw(value = amount);

        (,, int256 repaid) =
            vault(positionId).operate{ value: value }(nftId(), 0, amount < debt ? -amount.toInt256() : type(int256).min, address(0));

        actualAmount = (-repaid).toUint256();
        if (actualAmount < amount) asset.transferOut(address(this), payer, amount - actualAmount);
    }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256 balance)
        internal
        override
        returns (uint256 actualAmount)
    {
        bool isNative = asset == nativeToken;
        // Fluid has rounding issues, so sometimes they report a balance that can't actually be withdrawn
        int256 withdrawAmount = amount == balance ? type(int256).min : -amount.toInt256();

        (, int256 withdrawn,) = vault(positionId).operate(nftId(), withdrawAmount, 0, isNative ? address(this) : to);
        actualAmount = (-withdrawn).toUint256();

        if (isNative) nativeToken.transferOut(address(this), to, actualAmount);
    }

    function vault(PositionId positionId) public view returns (IFluidVault) {
        return resolver.getVaultAddress(uint40(Payload.unwrap(positionId.getPayload())));
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) nativeToken.deposit{ value: msg.value }();
    }

    function nftId() public view returns (uint256) {
        return NFT_ID_SLOT.getUint256Slot().value;
    }

    function nftId(uint256 value) internal {
        NFT_ID_SLOT.getUint256Slot().value = value;
    }

}

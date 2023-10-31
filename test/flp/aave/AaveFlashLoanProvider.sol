// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import { IPool } from "src/moneymarkets/aave/dependencies/IPool.sol";
import { IPoolDataProvider } from "src/moneymarkets/aave/dependencies/IPoolDataProvider.sol";
import { IPoolAddressesProvider } from "src/moneymarkets/aave/dependencies/IPoolAddressesProvider.sol";
import { IFlashLoanSimpleReceiver } from "./interfaces/IFlashLoanSimpleReceiver.sol";

import "../BaseWrapper.sol";

/// @dev Aave Flash Lender that uses the Aave Pool as source of liquidity.
/// Aave doesn't allow flow splitting or pushing repayments, so this wrapper is completely vanilla.
contract AaveFlashLoanProvider is BaseWrapper, IFlashLoanSimpleReceiver {

    error NotPool();
    error NotInitiator();

    // solhint-disable-next-line var-name-mixedcase
    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    // solhint-disable-next-line var-name-mixedcase
    IPool public immutable POOL;

    constructor(IPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
    }

    /// @inheritdoc IERC7399
    function maxFlashLoan(address asset) external view returns (uint256) {
        return _maxFlashLoan(asset);
    }

    /// @inheritdoc IERC7399
    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        uint256 max = _maxFlashLoan(asset);
        require(max > 0, "Unsupported currency");
        return amount >= max ? type(uint256).max : _flashFee(amount);
    }

    /// @inheritdoc IFlashLoanSimpleReceiver
    function executeOperation(address asset, uint256 amount, uint256 fee, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        if (msg.sender != address(POOL)) revert NotPool();
        if (initiator != address(this)) revert NotInitiator();

        _bridgeToCallback(asset, amount, fee, params);

        return true;
    }

    function _flashLoan(address asset, uint256 amount, bytes memory data) internal override {
        POOL.flashLoanSimple({ receiverAddress: address(this), asset: asset, amount: amount, params: data, referralCode: 0 });
    }

    function _maxFlashLoan(address asset) internal view returns (uint256 max) {
        IPoolDataProvider dataProvider = IPoolDataProvider(ADDRESSES_PROVIDER.getPoolDataProvider());
        (,,,,,,,, bool isActive, bool isFrozen) = dataProvider.getReserveConfigurationData(asset);

        (address aTokenAddress,,) = dataProvider.getReserveTokensAddresses(asset);

        max = !isFrozen && isActive && dataProvider.getFlashLoanEnabled(asset) ? IERC20(asset).balanceOf(aTokenAddress) : 0;
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount * (POOL.FLASHLOAN_PREMIUM_TOTAL() * 0.0001e18) / 1e18;
    }

}

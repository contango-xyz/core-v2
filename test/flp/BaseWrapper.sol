// SPDX-License-Identifier: MIT
// Thanks to ultrasecr.eth
pragma solidity ^0.8.19;

import "erc7399/IERC7399.sol";

import "src/libraries/ERC20Lib.sol";

/// @dev All ERC7399 flash loan wrappers have the same general structure.
/// - The ERC7399 `flash` function is the entry point for the flash loan.
/// - The wrapper calls the underlying lender flash lender on their non-ERC7399 flash lending call to borrow the funds.
/// -     The lender sends the funds to the wrapper.
/// -         The wrapper receives the callback from the lender.
/// -         The wrapper sends the funds to the loan receiver.
/// -         The wrapper calls the callback supplied by the original borrower.
/// -             The callback from the original borrower executes.
/// -         Depending on the lender, the wrapper may have to approve it to pull the repayment.
/// -         If there is any data to return, it is kept in a storage variable.
/// -         The wrapper exits the callback.
/// -     The lender verifies or pulls the repayment.
/// - The wrapper returns to the original borrower the stored result of its callback.
abstract contract BaseWrapper is IERC7399 {

    using ERC20Lib for IERC20;
    using SafeERC20 for IERC20;

    struct Data {
        address loanReceiver;
        address initiator;
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback;
        bytes initiatorData;
    }

    bytes internal _callbackResult;

    /// @inheritdoc IERC7399
    /// @dev The entry point for the ERC7399 flash loan. Packs data to convert the legacy flash loan into an ERC7399
    /// flash loan. Then it calls the legacy flash loan. Once the flash loan is done, checks if there is any return
    /// data and returns it.
    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata initiatorData,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    ) external returns (bytes memory result) {
        Data memory data = Data({ loanReceiver: loanReceiver, initiator: msg.sender, callback: callback, initiatorData: initiatorData });

        _flashLoan(asset, amount, abi.encode(data));

        result = _callbackResult;
        // Avoid storage write if not needed
        if (result.length > 0) delete _callbackResult;
        return result;
    }

    /// @dev Call the legacy flashloan function in the child contract. This is where we borrow from Aave, Uniswap, etc.
    function _flashLoan(address asset, uint256 amount, bytes memory params) internal virtual;

    /// @dev Handle the common parts of bridging the callback from legacy to ERC7399. Transfer the funds to the loan
    /// receiver. Call the callback supplied by the original borrower. Approve the repayment if necessary. If there is
    /// any result, it is kept in a storage variable to be retrieved on `flash` after the legacy flash loan is finished.
    function _bridgeToCallback(address asset, uint256 amount, uint256 fee, bytes memory params) internal {
        Data memory data = abi.decode(params, (Data));
        _transferAssets(asset, amount, data.loanReceiver);

        // call the callback and tell the callback receiver to repay the loan to this contract
        bytes memory result = data.callback(data.initiator, _repayTo(), address(asset), amount, fee, data.initiatorData);

        _approveRepayment(asset, amount, fee);

        if (result.length > 0) {
            // if there's any result, it is kept in a storage variable to be retrieved later in this tx
            _callbackResult = result;
        }
    }

    /// @dev Transfer the assets to the loan receiver.
    /// Override it if the provider can send the funds directly
    function _transferAssets(address asset, uint256 amount, address loanReceiver) internal virtual {
        IERC20(asset).transferOut(address(this), loanReceiver, amount);
    }

    /// @dev Approve the repayment of the loan to the provider if needed.
    /// Override it if the provider can receive the funds directly and you want to avoid the if condition
    function _approveRepayment(address asset, uint256 amount, uint256 fee) internal virtual {
        if (_repayTo() == address(this)) IERC20(asset).forceApprove(msg.sender, amount + fee);
    }

    /// @dev Where should the end client send the funds to repay the loan
    /// Override it if the provider can receive the funds directly
    function _repayTo() internal view virtual returns (address) {
        return address(this);
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

enum BalanceCheck {
    Both,
    From,
    To,
    None
}

interface IIsolationVault {

    function depositIntoVaultForDolomiteMargin(uint256 toAcc, uint256 amount) external;
    function openBorrowPosition(uint256 fromAcc, uint256 toAcc, uint256 amount) external payable;
    function transferFromPositionWithOtherToken(uint256 fromAcc, uint256 toAcc, uint256 marketId, uint256 amount, BalanceCheck balanceCheck)
        external;
    function transferIntoPositionWithOtherToken(uint256 fromAcc, uint256 toAcc, uint256 marketId, uint256 amount, BalanceCheck balanceCheck)
        external;
    function transferFromPositionWithUnderlyingToken(uint256 fromAcc, uint256 toAcc, uint256 amount) external;
    function withdrawFromVaultForDolomiteMargin(uint256 fromAcc, uint256 amount) external;

    function underlyingBalanceOf() external view returns (uint256);

}

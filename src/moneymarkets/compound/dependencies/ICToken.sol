//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./ComptrollerErrorReporter.sol";

interface ICToken is IERC20 {

    event AccrueInterest(uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);
    event Borrow(address borrower, uint256 borrowAmount, uint256 accountBorrows, uint256 totalBorrows);
    event Failure(uint256 error, uint256 info, uint256 detail);
    event LiquidateBorrow(address liquidator, address borrower, uint256 repayAmount, address cTokenCollateral, uint256 seizeTokens);
    event Mint(address minter, uint256 mintAmount, uint256 mintTokens);
    event NewAdmin(address oldAdmin, address newAdmin);
    event NewComptroller(address oldComptroller, address newComptroller);
    event NewMarketInterestRateModel(address oldInterestRateModel, address newInterestRateModel);
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);
    event NewReserveFactor(uint256 oldReserveFactorMantissa, uint256 newReserveFactorMantissa);
    event Redeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);
    event RepayBorrow(address payer, address borrower, uint256 repayAmount, uint256 accountBorrows, uint256 totalBorrows);
    event ReservesReduced(address admin, uint256 reduceAmount, uint256 newTotalReserves);

    function _acceptAdmin() external returns (uint256);
    function initialExchangeRateMantissa() external view returns (uint256);
    function liquidateBorrow(address borrower, address cTokenCollateral) external payable;
    function mint() external payable;
    function repayBorrow() external payable;
    function repayBorrowBehalf(address borrower) external payable;

    function _addReserves(uint256 addAmount) external returns (uint256);
    function _reduceReserves(uint256 reduceAmount) external returns (uint256);
    function _setComptroller(address newComptroller) external returns (uint256);
    function _setImplementation(address implementation_, bool allowResign, bytes memory becomeImplementationData) external;
    function _setInterestRateModel(address newInterestRateModel) external returns (uint256);
    function _setPendingAdmin(address newPendingAdmin) external returns (uint256);
    function _setReserveFactor(uint256 newReserveFactorMantissa) external returns (uint256);
    function accrualBlockNumber() external view returns (uint256);
    function accrueInterest() external returns (uint256);
    function admin() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (Error);
    function borrowBalanceCurrent(address account) external returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function borrowIndex() external view returns (uint256);
    function borrowRatePerBlock() external view returns (uint256);
    function comptroller() external view returns (address);
    function decimals() external view returns (uint8);
    function delegateToImplementation(bytes memory data) external returns (bytes memory);
    function delegateToViewImplementation(bytes memory data) external view returns (bytes memory);
    function exchangeRateCurrent() external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function getAccountSnapshot(address account) external view returns (uint256, uint256, uint256, uint256);
    function getCash() external view returns (uint256);
    function implementation() external view returns (address);
    function interestRateModel() external view returns (address);
    function isCToken() external view returns (bool);
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external returns (uint256);
    function mint(uint256 mintAmount) external returns (Error);
    function name() external view returns (string memory);
    function pendingAdmin() external view returns (address);
    function redeem(uint256 redeemTokens) external returns (Error);
    function redeemUnderlying(uint256 redeemAmount) external returns (Error);
    function repayBorrow(uint256 repayAmount) external returns (Error);
    function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (Error);
    function reserveFactorMantissa() external view returns (uint256);
    function seize(address liquidator, address borrower, uint256 seizeTokens) external returns (uint256);
    function supplyRatePerBlock() external view returns (uint256);
    function sweepToken(address token) external;
    function symbol() external view returns (string memory);
    function totalBorrows() external view returns (uint256);
    function totalBorrowsCurrent() external returns (uint256);
    function totalReserves() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function underlying() external view returns (IERC20);

}

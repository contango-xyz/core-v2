//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../moneymarkets/interfaces/IMoneyMarketView.sol";
import "../libraries/DataTypes.sol";
import "erc7399/IERC7399.sol";

struct OpenQuoteParams {
    PositionId positionId;
    uint256 quantity;
    uint256 leverage;
    int256 cashflow;
    Currency cashflowCcy;
    uint256 slippageTolerance;
}

struct CloseQuoteParams {
    PositionId positionId;
    uint256 quantity;
    uint256 leverage;
    int256 cashflow;
    Currency cashflowCcy;
    uint256 slippageTolerance;
}

struct ModifyQuoteParams {
    PositionId positionId;
    uint256 leverage;
    int256 cashflow;
    Currency cashflowCcy;
}

// What does the signed cost mean?
// In general, it'll be negative when quoting cost to open/increase, and positive when quoting cost to close/decrease.
// However, there are certain situations where that general rule may not hold true, for example when the qty delta is small and the collateral delta is big.
// Scenarios include:
//      * increase position by a tiny bit, but add a lot of collateral at the same time (aka. burn existing debt)
//      * decrease position by a tiny bit, withdraw a lot of excess equity at the same time (aka. issue new debt)
// For this reason, we cannot get rid of the signing, and make assumptions about in which direction the cost will go based on the qty delta alone.
// The effect (or likeliness of this coming into play) is much greater when the funding currency (quote) has a high interest rate.
struct Quote {
    uint256 quantity;
    Currency swapCcy;
    uint256 swapAmount;
    uint256 price;
    int256 cashflowUsed; // Collateral used to open/increase position with returned cost
    int256 minCashflow; // Minimum collateral needed to perform modification. If negative, it's the MAXIMUM amount that CAN be withdrawn.
    int256 maxCashflow; // Max collateral allowed to open/increase a position. If negative, it's the MINIMUM amount that HAS TO be withdrawn.
    OracleData oracleData;
    uint256 liquidationRatio; // The ratio at which a position becomes eligible for liquidation (underlyingCollateral/underlyingDebt)
    uint256 fee;
    Currency feeCcy;
    IERC7399 flashLoanProvider; // The provider used to calculate the flash loan fee
    uint256 transactionFees; // Fees paid for flash loans and any other necessary services
    bool fullyClose;
}

struct OracleData {
    uint256 collateral;
    uint256 debt;
    uint256 unit;
}

struct PositionStatus {
    uint256 collateral;
    uint256 debt;
    OracleData oracleData;
}

/// @title Interface to allow for quoting position operations
interface IQuoter {

    function setMoneyMarket(IMoneyMarketView moneyMarketView) external;

    function moneyMarkets(MoneyMarket) external view returns (IMoneyMarketView);

    function quoteOpen(OpenQuoteParams calldata params) external returns (Quote memory);

    function quoteClose(CloseQuoteParams calldata params) external returns (Quote memory);

    function quoteModify(ModifyQuoteParams calldata params) external returns (Quote memory);

    function positionStatus(PositionId positionId) external returns (PositionStatus memory);

}

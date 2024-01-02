// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

interface IPoolV2 {

    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRateMode,
        uint256 borrowRate,
        uint16 indexed referral
    );
    event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount, uint16 indexed referral);
    event FlashLoan(
        address indexed target, address indexed initiator, address indexed asset, uint256 amount, uint256 premium, uint16 referralCode
    );
    event LiquidationCall(
        address indexed collateralAsset,
        address indexed debtAsset,
        address indexed user,
        uint256 debtToCover,
        uint256 liquidatedCollateralAmount,
        address liquidator,
        bool receiveAToken,
        bool useAToken
    );
    event Paused();
    event RebalanceStableBorrowRate(address indexed reserve, address indexed user);
    event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount, bool useAToken);
    event ReserveDataUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );
    event ReserveUsedAsCollateralDisabled(address indexed reserve, address indexed user);
    event ReserveUsedAsCollateralEnabled(address indexed reserve, address indexed user);
    event SetReserveLimits(address indexed asset, uint256 depositLimit, uint256 borrowLimit, uint256 collateralUsageLimit);
    event Swap(address indexed reserve, address indexed user, uint256 rateMode);
    event Unpaused();
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);

    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveData {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 variableBorrowIndex;
        uint128 currentLiquidityRate;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint8 id;
    }

    struct ReserveLimits {
        uint256 depositLimit;
        uint256 borrowLimit;
        uint256 collateralUsageLimit;
    }

    struct UserConfigurationMap {
        uint256 data;
    }

    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint256);
    function LENDINGPOOL_REVISION() external view returns (uint256);
    function MAX_NUMBER_RESERVES() external view returns (uint256);
    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external view returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function finalizeTransfer(address asset, address from, address to, uint256 amount, uint256 balanceFromBefore, uint256 balanceToBefore)
        external;
    function flashLoan(
        address receiverAddress,
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory modes,
        address onBehalfOf,
        bytes memory params,
        uint16 referralCode
    ) external;
    function getAddressesProvider() external view returns (address);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function getReserveData(address asset) external view returns (ReserveData memory);
    function getReserveLimits(address asset) external view returns (ReserveLimits memory);
    function getReserveNormalizedIncome(address asset) external view returns (uint256);
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);
    function getReservesList() external view returns (address[] memory);
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function getUserConfiguration(address user) external view returns (UserConfigurationMap memory);
    function initReserve(
        address asset,
        address aTokenAddress,
        address stableDebtAddress,
        address variableDebtAddress,
        address interestRateStrategyAddress
    ) external;
    function initialize(address provider) external;
    function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) external;
    function liquidationCallUsingAgToken(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)
        external;
    function paused() external view returns (bool);
    function rebalanceStableBorrowRate(address asset, address user) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function repayUsingAgToken(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    function setConfiguration(address asset, uint256 configuration) external;
    function setPause(bool val) external;
    function setReserveInterestRateStrategyAddress(address asset, address rateStrategyAddress) external;
    function setReserveLimits(address asset, uint256 depositLimit, uint256 borrowLimit, uint256 collateralUsageLimit) external;
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
    function swapBorrowRateMode(address asset, uint256 rateMode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

}

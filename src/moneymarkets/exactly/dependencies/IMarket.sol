//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IAuditor.sol";
import "./IInterestRateModel.sol";

interface IMarket {

    error Disagreement(); // "0xb06dad04",
    error InsufficientProtocolLiquidity(); // "0x016a0d68",
    error MaturityOverflow(); // "0xa4f3107c",
    error NotAuditor(); // "0x5d5a323c",
    error SelfLiquidation(); // "0x44511af1",
    error UnmatchedPoolState(uint8, uint8); // "0x34e2603a",
    error UnmatchedPoolStates(uint8, uint8, uint8); // "0x7f2cef99",
    error ZeroBorrow(); // "0x774257f7",
    error ZeroDeposit(); // "0x56316e87",
    error ZeroRepay(); // "0x685e9235",
    error ZeroWithdraw(); // "0xb8cb6219"

    event AccumulatorAccrual(uint256 timestamp);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event BackupFeeRateSet(uint256 backupFeeRate);
    event Borrow(address indexed caller, address indexed receiver, address indexed borrower, uint256 assets, uint256 shares);
    event BorrowAtMaturity(
        uint256 indexed maturity, address caller, address indexed receiver, address indexed borrower, uint256 assets, uint256 fee
    );
    event DampSpeedSet(uint256 dampSpeedUp, uint256 dampSpeedDown);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event DepositAtMaturity(uint256 indexed maturity, address indexed caller, address indexed owner, uint256 assets, uint256 fee);
    event EarningsAccumulatorSmoothFactorSet(uint256 earningsAccumulatorSmoothFactor);
    event FixedEarningsUpdate(uint256 timestamp, uint256 indexed maturity, uint256 unassignedEarnings);
    event FloatingDebtUpdate(uint256 timestamp, uint256 utilization);
    event Initialized(uint8 version);
    event InterestRateModelSet(address indexed interestRateModel);
    event Liquidate(
        address indexed receiver,
        address indexed borrower,
        uint256 assets,
        uint256 lendersAssets,
        address indexed seizeMarket,
        uint256 seizedAssets
    );
    event MarketUpdate(
        uint256 timestamp,
        uint256 floatingDepositShares,
        uint256 floatingAssets,
        uint256 floatingBorrowShares,
        uint256 floatingDebt,
        uint256 earningsAccumulator
    );
    event MaxFuturePoolsSet(uint256 maxFuturePools);
    event Paused(address account);
    event PenaltyRateSet(uint256 penaltyRate);
    event Repay(address indexed caller, address indexed borrower, uint256 assets, uint256 shares);
    event RepayAtMaturity(
        uint256 indexed maturity, address indexed caller, address indexed borrower, uint256 assets, uint256 positionAssets
    );
    event ReserveFactorSet(uint256 reserveFactor);
    event RewardsControllerSet(address indexed rewardsController);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Seize(address indexed liquidator, address indexed borrower, uint256 assets);
    event SpreadBadDebt(address indexed borrower, uint256 assets);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TreasurySet(address indexed treasury, uint256 treasuryFeeRate);
    event Unpaused(address account);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event WithdrawAtMaturity(
        uint256 indexed maturity, address caller, address indexed receiver, address indexed owner, uint256 positionAssets, uint256 assets
    );

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);
    function accountSnapshot(address account) external view returns (uint256, uint256);
    function accounts(address) external view returns (uint256 fixedDeposits, uint256 fixedBorrows, uint256 floatingBorrowShares);
    function allowance(address, address) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function asset() external view returns (IERC20);
    function auditor() external view returns (IAuditor);
    function backupFeeRate() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function borrow(uint256 assets, address receiver, address borrower) external returns (uint256 borrowShares);
    function borrowAtMaturity(uint256 maturity, uint256 assets, uint256 maxAssets, address receiver, address borrower)
        external
        returns (uint256 assetsOwed);
    function clearBadDebt(address borrower) external;
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function dampSpeedDown() external view returns (uint256);
    function dampSpeedUp() external view returns (uint256);
    function decimals() external view returns (uint8);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function depositAtMaturity(uint256 maturity, uint256 assets, uint256 minAssetsRequired, address receiver)
        external
        returns (uint256 positionAssets);
    function earningsAccumulator() external view returns (uint256);
    function earningsAccumulatorSmoothFactor() external view returns (uint128);
    function fixedBorrowPositions(uint256, address) external view returns (uint256 principal, uint256 fee);
    function fixedDepositPositions(uint256, address) external view returns (uint256 principal, uint256 fee);
    function fixedPoolBalance(uint256 maturity) external view returns (uint256, uint256);
    function fixedPoolBorrowed(uint256 maturity) external view returns (uint256);
    function fixedPools(uint256)
        external
        view
        returns (uint256 borrowed, uint256 supplied, uint256 unassignedEarnings, uint256 lastAccrual);
    function floatingAssets() external view returns (uint256);
    function floatingAssetsAverage() external view returns (uint256);
    function floatingBackupBorrowed() external view returns (uint256);
    function floatingDebt() external view returns (uint256);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(
        uint8 maxFuturePools_,
        uint128 earningsAccumulatorSmoothFactor_,
        address interestRateModel_,
        uint256 penaltyRate_,
        uint256 backupFeeRate_,
        uint128 reserveFactor_,
        uint256 dampSpeedUp_,
        uint256 dampSpeedDown_
    ) external;
    function interestRateModel() external view returns (IInterestRateModel);
    function lastAccumulatorAccrual() external view returns (uint32);
    function lastAverageUpdate() external view returns (uint32);
    function lastFloatingDebtUpdate() external view returns (uint32);
    function liquidate(address borrower, uint256 maxAssets, address seizeMarket) external returns (uint256 repaidAssets);
    function maxDeposit(address) external view returns (uint256);
    function maxFuturePools() external view returns (uint8);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function name() external view returns (string memory);
    function nonces(address) external view returns (uint256);
    function pause() external;
    function paused() external view returns (bool);
    function penaltyRate() external view returns (uint256);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function previewBorrow(uint256 assets) external view returns (uint256);
    function previewDebt(address borrower) external view returns (uint256 debt);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewFloatingAssetsAverage() external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewRefund(uint256 shares) external view returns (uint256);
    function previewRepay(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function refund(uint256 borrowShares, address borrower) external returns (uint256 assets, uint256 actualShares);
    function renounceRole(bytes32 role, address account) external;
    function repay(uint256 assets, address borrower) external returns (uint256 actualRepay, uint256 borrowShares);
    function repayAtMaturity(uint256 maturity, uint256 positionAssets, uint256 maxAssets, address borrower)
        external
        returns (uint256 actualRepayAssets);
    function reserveFactor() external view returns (uint128);
    function revokeRole(bytes32 role, address account) external;
    function rewardsController() external view returns (address);
    function seize(address liquidator, address borrower, uint256 assets) external;
    function setBackupFeeRate(uint256 backupFeeRate_) external;
    function setDampSpeed(uint256 up, uint256 down) external;
    function setEarningsAccumulatorSmoothFactor(uint128 earningsAccumulatorSmoothFactor_) external;
    function setInterestRateModel(address interestRateModel_) external;
    function setMaxFuturePools(uint8 futurePools) external;
    function setPenaltyRate(uint256 penaltyRate_) external;
    function setReserveFactor(uint128 reserveFactor_) external;
    function setRewardsController(address rewardsController_) external;
    function setTreasury(address treasury_, uint256 treasuryFeeRate_) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256);
    function totalFloatingBorrowAssets() external view returns (uint256);
    function totalFloatingBorrowShares() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 shares) external returns (bool);
    function transferFrom(address from, address to, uint256 shares) external returns (bool);
    function treasury() external view returns (address);
    function treasuryFeeRate() external view returns (uint256);
    function unpause() external;
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function withdrawAtMaturity(uint256 maturity, uint256 positionAssets, uint256 minAssetsRequired, address receiver, address owner)
        external
        returns (uint256 assetsDiscounted);

}

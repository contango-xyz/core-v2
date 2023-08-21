//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IExactlyRewardsController {

    event Accrue(
        address indexed market,
        address indexed reward,
        address indexed account,
        bool operation,
        uint256 accountIndex,
        uint256 operationIndex,
        uint256 rewardsAccrued
    );
    event Claim(address indexed account, address indexed reward, address indexed to, uint256 amount);
    event DistributionSet(address indexed market, address indexed reward, Config config);
    event IndexUpdate(
        address indexed market,
        address indexed reward,
        uint256 borrowIndex,
        uint256 depositIndex,
        uint256 newUndistributed,
        uint256 lastUpdate
    );
    event Initialized(uint8 version);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    struct Config {
        address market;
        address reward;
        address priceFeed;
        uint32 start;
        uint256 distributionPeriod;
        uint256 targetDebt;
        uint256 totalDistribution;
        uint256 undistributedFactor;
        int128 flipSpeed;
        uint64 compensationFactor;
        uint64 transitionFactor;
        uint64 borrowAllocationWeightFactor;
        uint64 depositAllocationWeightAddend;
        uint64 depositAllocationWeightFactor;
    }

    struct MarketOperation {
        address market;
        bool[] operations;
    }

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function UTILIZATION_CAP() external view returns (uint256);
    function accountOperation(address account, address market, bool operation, address reward) external view returns (uint256, uint256);
    function allClaimable(address account, address reward) external view returns (uint256 unclaimedRewards);
    function allMarketsOperations() external view returns (MarketOperation[] memory marketOps);
    function allRewards() external view returns (address[] memory);
    function availableRewardsCount(address market) external view returns (uint256);
    function claim(MarketOperation[] memory marketOps, address to, address[] memory rewardsList)
        external
        returns (address[] memory, uint256[] memory claimedAmounts);
    function claimAll(address to) external returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
    function claimable(MarketOperation[] memory marketOps, address account, address reward)
        external
        view
        returns (uint256 unclaimedRewards);
    function config(Config[] memory configs) external;
    function distribution(address) external view returns (uint8 availableRewardsCount, uint256 baseUnit);
    function distributionTime(address market, address reward) external view returns (uint32, uint32, uint32);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function handleBorrow(address account) external;
    function handleDeposit(address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize() external;
    function marketList(uint256) external view returns (address);
    function previewAllocation(address market, address reward, uint256 deltaTime)
        external
        view
        returns (uint256 borrowIndex, uint256 depositIndex, uint256 newUndistributed);
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function rewardConfig(address market, address reward) external view returns (Config memory);
    function rewardEnabled(address) external view returns (bool);
    function rewardIndexes(address market, address reward) external view returns (uint256, uint256, uint256);
    function rewardList(uint256) external view returns (address);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function withdraw(address asset, address to) external;

}

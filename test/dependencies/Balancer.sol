// SPDX-License-Identifier: unlicenced
pragma solidity ^0.8.10;

interface IBalancerVault {

    event AuthorizerChanged(address indexed newAuthorizer);
    event ExternalBalanceTransfer(address indexed token, address indexed sender, address recipient, uint256 amount);
    event FlashLoan(address indexed recipient, address indexed token, uint256 amount, uint256 feeAmount);
    event InternalBalanceChanged(address indexed user, address indexed token, int256 delta);
    event PausedStateChanged(bool paused);
    event PoolBalanceChanged(
        bytes32 indexed poolId, address indexed liquidityProvider, address[] tokens, int256[] deltas, uint256[] protocolFeeAmounts
    );
    event PoolBalanceManaged(
        bytes32 indexed poolId, address indexed assetManager, address indexed token, int256 cashDelta, int256 managedDelta
    );
    event PoolRegistered(bytes32 indexed poolId, address indexed poolAddress, uint8 specialization);
    event RelayerApprovalChanged(address indexed relayer, address indexed sender, bool approved);
    event Swap(bytes32 indexed poolId, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event TokensDeregistered(bytes32 indexed poolId, address[] tokens);
    event TokensRegistered(bytes32 indexed poolId, address[] tokens, address[] assetManagers);

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct PoolBalanceOp {
        uint8 kind;
        bytes32 poolId;
        address token;
        uint256 amount;
    }

    struct SingleSwap {
        bytes32 poolId;
        uint8 kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct UserBalanceOp {
        uint8 kind;
        address asset;
        uint256 amount;
        address sender;
        address recipient;
    }

    function WETH() external view returns (address);
    function batchSwap(
        uint8 kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory assetDeltas);
    function deregisterTokens(bytes32 poolId, address[] memory tokens) external;
    function exitPool(bytes32 poolId, address sender, address recipient, ExitPoolRequest memory request) external;
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData) external;
    function getActionId(bytes4 selector) external view returns (bytes32);
    function getAuthorizer() external view returns (address);
    function getDomainSeparator() external view returns (bytes32);
    function getInternalBalance(address user, address[] memory tokens) external view returns (uint256[] memory balances);
    function getNextNonce(address user) external view returns (uint256);
    function getPausedState() external view returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
    function getPool(bytes32 poolId) external view returns (IBalancerWeightedPool, uint8);
    function getPoolTokenInfo(bytes32 poolId, address token)
        external
        view
        returns (uint256 cash, uint256 managed, uint256 lastChangeBlock, address assetManager);
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);
    function getProtocolFeesCollector() external view returns (address);
    function hasApprovedRelayer(address user, address relayer) external view returns (bool);
    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;
    function managePoolBalance(PoolBalanceOp[] memory ops) external;
    function manageUserBalance(UserBalanceOp[] memory ops) external payable;
    function queryBatchSwap(uint8 kind, BatchSwapStep[] memory swaps, address[] memory assets, FundManagement memory funds)
        external
        returns (int256[] memory);
    function registerPool(uint8 specialization) external returns (bytes32);
    function registerTokens(bytes32 poolId, address[] memory tokens, address[] memory assetManagers) external;
    function setAuthorizer(address newAuthorizer) external;
    function setPaused(bool paused) external;
    function setRelayerApproval(address sender, address relayer, bool approved) external;
    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        payable
        returns (uint256 amountCalculated);

}

interface IBalancerWeightedPool {

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event PausedStateChanged(bool paused);
    event ProtocolFeePercentageCacheUpdated(uint256 indexed feeType, uint256 protocolFeePercentage);
    event RecoveryModeStateChanged(bool enabled);
    event SwapFeePercentageChanged(uint256 swapFeePercentage);
    event Transfer(address indexed from, address indexed to, uint256 value);

    struct SwapRequest {
        uint8 kind;
        address tokenIn;
        address tokenOut;
        uint256 amount;
        bytes32 poolId;
        uint256 lastChangeBlock;
        address from;
        address to;
        bytes userData;
    }

    struct NewPoolParams {
        string name;
        string symbol;
        address[] tokens;
        uint256[] normalizedWeights;
        address[] rateProviders;
        address[] assetManagers;
        uint256 swapFeePercentage;
    }

    function DELEGATE_PROTOCOL_SWAP_FEES_SENTINEL() external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 amount) external returns (bool);
    function disableRecoveryMode() external;
    function enableRecoveryMode() external;
    function getATHRateProduct() external view returns (uint256);
    function getActionId(bytes4 selector) external view returns (bytes32);
    function getActualSupply() external view returns (uint256);
    function getAuthorizer() external view returns (address);
    function getDomainSeparator() external view returns (bytes32);
    function getInvariant() external view returns (uint256);
    function getLastPostJoinExitInvariant() external view returns (uint256);
    function getNextNonce(address account) external view returns (uint256);
    function getNormalizedWeights() external view returns (uint256[] memory);
    function getOwner() external view returns (address);
    function getPausedState() external view returns (bool paused, uint256 pauseWindowEndTime, uint256 bufferPeriodEndTime);
    function getPoolId() external view returns (bytes32);
    function getProtocolFeePercentageCache(uint256 feeType) external view returns (uint256);
    function getProtocolFeesCollector() external view returns (address);
    function getProtocolSwapFeeDelegation() external view returns (bool);
    function getRateProviders() external view returns (address[] memory);
    function getScalingFactors() external view returns (uint256[] memory);
    function getSwapFeePercentage() external view returns (uint256);
    function getVault() external view returns (address);
    function inRecoveryMode() external view returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory, uint256[] memory);
    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256[] memory, uint256[] memory);
    function onSwap(SwapRequest memory request, uint256 balanceTokenIn, uint256 balanceTokenOut) external returns (uint256);
    function pause() external;
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptOut, uint256[] memory amountsIn);
    function setAssetManagerPoolConfig(address token, bytes memory poolConfig) external;
    function setSwapFeePercentage(uint256 swapFeePercentage) external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function unpause() external;
    function updateProtocolFeePercentageCache() external;
    function version() external view returns (string memory);

}

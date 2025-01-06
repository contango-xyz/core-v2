// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ISiloRepository {

    struct AssetConfig {
        uint64 maxLoanToValue;
        uint64 liquidationThreshold;
        address interestRateModel;
    }

    struct Fees {
        uint64 entryFee;
        uint64 protocolShareFee;
        uint64 protocolLiquidationFee;
    }

    error AssetAlreadyAdded();
    error AssetIsNotABridge();
    error AssetIsZero();
    error BridgeAssetIsZero();
    error ConfigDidNotChange();
    error EmptyBridgeAssets();
    error FeesDidNotChange();
    error GlobalLimitDidNotChange();
    error GlobalPauseDidNotChange();
    error InterestRateModelDidNotChange();
    error InvalidEntryFee();
    error InvalidInterestRateModel();
    error InvalidLTV();
    error InvalidLiquidationThreshold();
    error InvalidNotificationReceiver();
    error InvalidPriceProvidersRepository();
    error InvalidProtocolLiquidationFee();
    error InvalidProtocolShareFee();
    error InvalidSiloFactory();
    error InvalidSiloRouter();
    error InvalidSiloVersion();
    error InvalidTokensFactory();
    error LastBridgeAsset();
    error LiquidationThresholdDidNotChange();
    error ManagerDidNotChange();
    error ManagerIsZero();
    error MaxLiquidityDidNotChange();
    error MaximumLTVDidNotChange();
    error NoPriceProviderForAsset();
    error NotificationReceiverDidNotChange();
    error OnlyManager();
    error OnlyOwnerOrManager();
    error PriceProviderRepositoryDidNotChange();
    error RouterDidNotChange();
    error SiloAlreadyExistsForAsset();
    error SiloAlreadyExistsForBridgeAssets();
    error SiloDoesNotExist();
    error SiloIsZero();
    error SiloMaxLiquidityDidNotChange();
    error SiloNotAllowedForBridgeAsset();
    error SiloPauseDidNotChange();
    error SiloVersionDoesNotExist();
    error TokenIsNotAContract();
    error VersionForAssetDidNotChange();

    function assetConfigs(ISilo, IERC20) external view returns (AssetConfig memory);
    function bridgePool() external view returns (address);
    function entryFee() external view returns (uint256);
    function fees() external view returns (uint64 entryFee, uint64 protocolShareFee, uint64 protocolLiquidationFee);
    function getBridgeAssets() external view returns (address[] memory);
    function getInterestRateModel(ISilo _silo, IERC20 asset) external view returns (IInterestRateModelV2 model);
    function getLiquidationThreshold(ISilo _silo, IERC20 asset) external view returns (uint256);
    function getMaxSiloDepositsValue(ISilo _silo, IERC20 asset) external view returns (uint256);
    function getMaximumLTV(ISilo _silo, IERC20 asset) external view returns (uint256);
    function getNotificationReceiver(ISilo) external view returns (ISiloIncentivesController);
    function getRemovedBridgeAssets() external view returns (address[] memory);
    function getSilo(IERC20) external view returns (ISilo);
    function getVersionForAsset(address) external view returns (uint128);
    function isPaused() external view returns (bool globalPause);
    function isSilo(ISilo _silo) external view returns (bool);
    function isSiloPaused(ISilo _silo, IERC20 asset) external view returns (bool);
    function manager() external view returns (address);
    function maxLiquidity() external view returns (bool globalLimit, uint256 defaultMaxLiquidity);
    function priceProvidersRepository() external view returns (ISiloPriceProvidersRepository);
    function protocolLiquidationFee() external view returns (uint256);
    function protocolShareFee() external view returns (uint256);
    function router() external view returns (address);
    function siloFactory(uint256) external view returns (address);
    function siloReverse(address) external view returns (address);
    function siloVersion() external view returns (uint128 byDefault, uint128 latest);
    function tokensFactory() external view returns (address);

}

interface ISilo {

    enum AssetStatus {
        Undefined,
        Active,
        Removed
    }

    struct AssetInterestData {
        uint256 harvestedProtocolFees;
        uint256 protocolFees;
        uint64 interestRateTimestamp;
        AssetStatus status;
    }

    struct AssetStorage {
        IERC20 collateralToken;
        IERC20 collateralOnlyToken;
        IERC20 debtToken;
        uint256 totalDeposits;
        uint256 collateralOnlyDeposits;
        uint256 totalBorrowAmount;
    }

    struct UtilizationData {
        uint256 totalDeposits;
        uint256 totalBorrowAmount;
        uint64 interestRateTimestamp;
    }

    error AssetDoesNotExist();
    error BorrowNotPossible();
    error DepositNotPossible();
    error DepositsExceedLimit();
    error DifferentArrayLength();
    error InvalidRepository();
    error InvalidSiloVersion();
    error LiquidationReentrancyCall();
    error MaximumLTVReached();
    error NotEnoughDeposits();
    error NotEnoughLiquidity();
    error NotSolvent();
    error OnlyRouter();
    error Paused();
    error TokenIsNotAContract();
    error UnexpectedEmptyReturn();
    error UnsupportedLTVType();
    error UserIsZero();
    error ZeroAssets();
    error ZeroShares();

    function VERSION() external view returns (uint128);
    function accrueInterest(IERC20 asset) external returns (uint256 interest);
    function assetStorage(IERC20 asset) external view returns (AssetStorage memory);
    function borrow(IERC20 asset, uint256 _amount) external returns (uint256 debtAmount, uint256 debtShare);
    function borrowPossible(IERC20 asset, address _borrower) external view returns (bool);
    function deposit(IERC20 asset, uint256 _amount, bool _collateralOnly)
        external
        returns (uint256 collateralAmount, uint256 collateralShare);
    function depositPossible(IERC20 asset, address _depositor) external view returns (bool);
    function flashLiquidate(address[] memory _users, bytes memory _flashReceiverData)
        external
        returns (IERC20[] memory assets, uint256[][] memory receivedCollaterals, uint256[][] memory shareAmountsToRepay);
    function getAssets() external view returns (IERC20[] memory assets);
    function getAssetsWithState() external view returns (IERC20[] memory assets, AssetStorage[] memory assetsStorage);
    function harvestProtocolFees() external returns (uint256[] memory harvestedAmounts);
    function initAssetsTokens() external;
    function interestData(IERC20 asset) external view returns (AssetInterestData memory);
    function isSolvent(address _user) external view returns (bool);
    function liquidity(IERC20 asset) external view returns (uint256);
    function repay(IERC20 asset, uint256 _amount) external returns (uint256 repaidAmount, uint256 repaidShare);
    function repayFor(address _asset, address _borrower, uint256 _amount) external returns (uint256 repaidAmount, uint256 repaidShare);
    function siloAsset() external view returns (IERC20);
    function siloRepository() external view returns (ISiloRepository);
    function syncBridgeAssets() external;
    function utilizationData(IERC20 asset) external view returns (UtilizationData memory data);
    function withdraw(IERC20 asset, uint256 _amount, bool _collateralOnly)
        external
        returns (uint256 withdrawnAmount, uint256 withdrawnShare);

}

interface ISiloLens {

    error DifferentArrayLength();
    error InvalidRepository();
    error UnsupportedLTVType();
    error ZeroAssets();

    function balanceOfUnderlying(uint256 _assetTotalDeposits, IERC20 _shareToken, address _user) external view returns (uint256);
    function borrowAPY(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function borrowShare(ISilo _silo, IERC20 _asset, address _user) external view returns (uint256);
    function calcFee(uint256 _amount) external view returns (uint256);
    function calculateBorrowValue(ISilo _silo, address _user, IERC20 _asset) external view returns (uint256);
    function calculateCollateralValue(ISilo _silo, address _user, IERC20 _asset) external view returns (uint256);
    function collateralBalanceOfUnderlying(ISilo _silo, IERC20 _asset, address _user) external view returns (uint256);
    function collateralOnlyDeposits(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function debtBalanceOfUnderlying(ISilo _silo, IERC20 _asset, address _user) external view returns (uint256);
    function depositAPY(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function getBorrowAmount(ISilo _silo, IERC20 _asset, address _user, uint256 _timestamp) external view returns (uint256);
    function getModel(ISilo _silo, IERC20 _asset) external view returns (address);
    function getUserLTV(ISilo _silo, address _user) external view returns (uint256 userLTV);
    function getUserLiquidationThreshold(ISilo _silo, address _user) external view returns (uint256 liquidationThreshold);
    function getUserMaximumLTV(ISilo _silo, address _user) external view returns (uint256 maximumLTV);
    function getUtilization(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function hasPosition(ISilo _silo, address _user) external view returns (bool);
    function inDebt(ISilo _silo, address _user) external view returns (bool);
    function liquidity(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function protocolFees(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function siloRepository() external view returns (ISiloRepository);
    function totalBorrowAmount(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function totalBorrowAmountWithInterest(ISilo _silo, IERC20 _asset) external view returns (uint256 _totalBorrowAmount);
    function totalBorrowShare(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function totalDeposits(ISilo _silo, IERC20 _asset) external view returns (uint256);
    function totalDepositsWithInterest(ISilo _silo, IERC20 _asset) external view returns (uint256 _totalDeposits);

}

interface ISiloPriceProvidersRepository {

    error AssetNotSupported();
    error InvalidPriceProvider();
    error InvalidPriceProviderQuoteToken();
    error InvalidRepository();
    error ManagerDidNotChange();
    error ManagerIsZero();
    error OnlyManager();
    error OnlyOwnerOrManager();
    error OnlyRepository();
    error PriceProviderAlreadyExists();
    error PriceProviderDoesNotExist();
    error PriceProviderNotRegistered();
    error QuoteTokenNotSupported();
    error TokenIsNotAContract();

    function QUOTE_TOKEN_DECIMALS() external view returns (uint256);
    function getPrice(IERC20 _asset) external view returns (uint256);
    function isPriceProvider(address _provider) external view returns (bool);
    function priceProviders(address) external view returns (address);
    function providerList() external view returns (address[] memory);
    function providersCount() external view returns (uint256);
    function providersReadyForAsset(IERC20 _asset) external view returns (bool);
    function quoteToken() external view returns (address);
    function siloRepository() external view returns (address);

}

interface ISiloIncentivesController {

    struct AssetData {
        uint256 index;
        uint256 emissionPerSecond;
        uint256 lastUpdateTimestamp;
    }

    error ClaimerUnauthorized();
    error IndexOverflow();
    error IndexOverflowAtEmissionsPerSecond();
    error InvalidConfiguration();
    error InvalidToAddress();
    error InvalidUserAddress();
    error OnlyEmissionManager();

    function DISTRIBUTION_END() external view returns (uint256);
    function EMISSION_MANAGER() external view returns (address);
    function PRECISION() external view returns (uint8);
    function REVISION() external view returns (uint256);
    function REWARD_TOKEN() external view returns (IERC20);
    function TEN_POW_PRECISION() external view returns (uint256);
    function claimRewards(IERC20[] memory assets, uint256 amount, address to) external returns (uint256);
    function claimRewardsOnBehalf(IERC20[] memory assets, uint256 amount, address user, address to) external returns (uint256);
    function claimRewardsToSelf(IERC20[] memory assets, uint256 amount) external returns (uint256);
    function configureAssets(IERC20[] memory assets, uint256[] memory emissionsPerSecond) external;
    function getAssetData(IERC20 asset) external view returns (AssetData memory);
    function getClaimer(address user) external view returns (address);
    function getDistributionEnd() external view returns (uint256);
    function getRewardsBalance(IERC20[] memory assets, address user) external view returns (uint256);
    function getUserAssetData(address user, address asset) external view returns (uint256);
    function getUserUnclaimedRewards(address _user) external view returns (uint256);
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;
    function notificationReceiverPing() external pure returns (bytes4);
    function onAfterTransfer(address, address _from, address _to, uint256 _amount) external;
    function rescueRewards() external;
    function setClaimer(address user, address caller) external;
    function setDistributionEnd(uint256 distributionEnd) external;

}

interface IInterestRateModelV2 {

    // solhint-disable var-name-mixedcase

    struct Config {
        int256 uopt;
        int256 ucrit;
        int256 ulow;
        int256 ki;
        int256 kcrit;
        int256 klow;
        int256 klin;
        int256 beta;
        int256 ri;
        int256 Tcrit;
    }

    error InvalidBeta();
    error InvalidKcrit();
    error InvalidKi();
    error InvalidKlin();
    error InvalidKlow();
    error InvalidRi();
    error InvalidTcrit();
    error InvalidTimestamps();
    error InvalidUcrit();
    error InvalidUlow();
    error InvalidUopt();

    event ConfigUpdate(address indexed silo, address indexed asset, Config config);
    event OwnershipPending(address indexed newPendingOwner);
    event OwnershipTransferred(address indexed newOwner);

    function ASSET_DATA_OVERFLOW_LIMIT() external view returns (uint256);
    function DP() external view returns (uint256);
    function RCOMP_MAX() external view returns (uint256);
    function X_MAX() external view returns (int256);
    function acceptOwnership() external;
    function calculateCompoundInterestRate(
        Config memory _c,
        uint256 _totalDeposits,
        uint256 _totalBorrowAmount,
        uint256 _interestRateTimestamp,
        uint256 _blockTimestamp
    ) external pure returns (uint256 rcomp, int256 ri, int256 Tcrit);
    function calculateCompoundInterestRateWithOverflowDetection(
        Config memory _c,
        uint256 _totalDeposits,
        uint256 _totalBorrowAmount,
        uint256 _interestRateTimestamp,
        uint256 _blockTimestamp
    ) external pure returns (uint256 rcomp, int256 ri, int256 Tcrit, bool overflow);
    function calculateCurrentInterestRate(
        Config memory _c,
        uint256 _totalDeposits,
        uint256 _totalBorrowAmount,
        uint256 _interestRateTimestamp,
        uint256 _blockTimestamp
    ) external pure returns (uint256 rcur);
    function config(address, address)
        external
        view
        returns (
            int256 uopt,
            int256 ucrit,
            int256 ulow,
            int256 ki,
            int256 kcrit,
            int256 klow,
            int256 klin,
            int256 beta,
            int256 ri,
            int256 Tcrit
        );
    function getCompoundInterestRate(address _silo, address _asset, uint256 _blockTimestamp) external view returns (uint256 rcomp);
    function getCompoundInterestRateAndUpdate(address _asset, uint256 _blockTimestamp) external returns (uint256 rcomp);
    function getConfig(ISilo _silo, IERC20 _asset) external view returns (Config memory);
    function getCurrentInterestRate(address _silo, address _asset, uint256 _blockTimestamp) external view returns (uint256 rcur);
    function interestRateModelPing() external pure returns (bytes4);
    function migrationFromV1(address[] memory _silos, address _siloRepository) external;
    function overflowDetected(address _silo, address _asset, uint256 _blockTimestamp) external view returns (bool overflow);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function removePendingOwnership() external;
    function renounceOwnership() external;
    function setConfig(address _silo, address _asset, Config memory _config) external;
    function transferOwnership(address newOwner) external;
    function transferPendingOwnership(address newPendingOwner) external;

    // solhint-enable var-name-mixedcase

}

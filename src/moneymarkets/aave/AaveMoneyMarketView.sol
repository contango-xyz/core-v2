//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IAaveRewardsController.sol";
import "./dependencies/IPool.sol";
import "./dependencies/IPoolAddressesProvider.sol";
import "./dependencies/IPoolDataProviderV31.sol";
import "./dependencies/IDefaultReserveInterestRateStrategyV3.sol";
import "./dependencies/IDefaultReserveInterestRateStrategyV31.sol";

import "../BaseMoneyMarketView.sol";
import { isBitSet } from "../../libraries/BitFlags.sol";
import { E_MODE } from "./AaveMoneyMarket.sol";
import "../../libraries/Arrays.sol";
import { MM_AAVE } from "script/constants.sol";

contract AaveMoneyMarketView is BaseMoneyMarketView {

    enum Version {
        V2,
        V3,
        V32
    }

    struct IRMData {
        uint256 unbacked;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 averageStableBorrowRate;
        uint256 reserveFactor;
        uint256 aTokenReserveBalance;
        uint256 optimalUsageRatio;
        uint256 maxExcessUsageRatio;
        uint256 variableRateSlope1;
        uint256 variableRateSlope2;
        uint256 baseVariableBorrowRate;
    }

    error OracleBaseCurrencyNotUSD();

    using Math for *;

    IPoolAddressesProvider public immutable poolAddressesProvider;
    IAaveRewardsController public immutable rewardsController;
    Version public immutable version;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        IPoolAddressesProvider _poolAddressesProvider,
        IAaveRewardsController _rewardsController,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        Version _version
    ) BaseMoneyMarketView(_moneyMarketId, _moneyMarketName, _contango, _nativeToken, _nativeUsdOracle) {
        poolAddressesProvider = _poolAddressesProvider;
        rewardsController = _rewardsController;
        version = _version;
    }

    // ====== IMoneyMarketView =======

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        (balances_.collateral,,,,,,,,) = dataProvider().getUserReserveData(address(collateralAsset), account);
        (,, balances_.debt,,,,,,) = dataProvider().getUserReserveData(address(debtAsset), account);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return oracle().BASE_CURRENCY_UNIT();
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        try oracle().getAssetPrice(asset) returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    function _thresholds(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        uint256 eModeCategory = positionId.getNumber() > 0
            ? pool().getUserEMode(_account(positionId)) // Backwards compatibility
            : isBitSet(positionId.getFlags(), E_MODE) ? uint32(positionId.getPayloadNoFlags()) : 0;

        if (eModeCategory == 0) (, ltv, liquidationThreshold,,,,,,,) = dataProvider().getReserveConfigurationData(address(collateralAsset));
        else (, ltv, liquidationThreshold) = pool().getEModeCategoryData(uint8(eModeCategory));

        ltv *= 1e14;
        liquidationThreshold *= 1e14;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _borrowingLiquidity(debtAsset);
        lending = _lendingLiquidity(collateralAsset);

        uint256 debtCeiling = dataProvider().getDebtCeiling(address(collateralAsset));
        if (debtCeiling > 0) {
            if (address(oracle().BASE_CURRENCY()) != address(0)) revert OracleBaseCurrencyNotUSD();
            uint256 debtAssetPrice = oracle().getAssetPrice(debtAsset);

            uint256 available = (debtCeiling - pool().getReserveData(collateralAsset).isolationModeTotalDebt)
                * (oracle().BASE_CURRENCY_UNIT() / (10 ** dataProvider().getDebtCeilingDecimals()));

            borrowing = Math.min(borrowing, available * 10 ** debtAsset.decimals() / debtAssetPrice);
        }
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _apy({ rate: pool().getReserveData(debtAsset).currentVariableBorrowRate / 1e9, perSeconds: 365 days });
        lending = _apy({ rate: pool().getReserveData(collateralAsset).currentLiquidityRate / 1e9, perSeconds: 365 days });
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        if (rewardsController != IAaveRewardsController(address(0))) {
            address account = positionId.getNumber() > 0 ? _account(positionId) : address(0);
            borrowing = _asRewards(account, debtAsset, true);
            lending = _asRewards(account, collateralAsset, false);
        }
    }

    function _irmRaw(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (bytes memory data)
    {
        address account = positionId.getNumber() > 0 ? _account(positionId) : address(0);

        if (version == Version.V32) {
            return abi.encode(collectRawDataV32(account, collateralAsset, debtAsset));
        } else {
            return abi.encode(
                collectIrmDataV2V3(collateralAsset),
                collectIrmDataV2V3(debtAsset),
                rawRewardData(account, collateralAsset, false),
                rawRewardData(account, debtAsset, true)
            );
        }
    }

    struct RawDataV32 {
        IrmDataV32 baseData;
        IrmDataV32 quoteData;
        RewardRawData[] baseRewards;
        RewardRawData[] quoteRewards;
    }

    // Visible so we can decode using wagmi
    function collectRawDataV32(address account, IERC20 collateralAsset, IERC20 debtAsset) public view returns (RawDataV32 memory data) {
        data.baseData = _collectIrmDataV32(collateralAsset);
        data.quoteData = _collectIrmDataV32(debtAsset);
        data.baseRewards = rawRewardData(account, collateralAsset, false);
        data.quoteRewards = rawRewardData(account, debtAsset, true);
    }

    struct IrmDataV32 {
        IDefaultReserveInterestRateStrategyV31.InterestRateDataRay interestRateData;
        IDefaultReserveInterestRateStrategyV31.CalculateInterestRatesParams params;
    }

    function _collectIrmDataV32(IERC20 asset) internal view returns (IrmDataV32 memory data) {
        IPoolDataProviderV31 _dataProvider = IPoolDataProviderV31(address(dataProvider()));
        IDefaultReserveInterestRateStrategyV31 irStrategy =
            IDefaultReserveInterestRateStrategyV31(_dataProvider.getInterestRateStrategyAddress(address(asset)));
        data.interestRateData = irStrategy.getInterestRateData(address(asset));

        IPoolDataProviderV3.ReserveData memory reserveData = _dataProvider.getReserveData(address(asset));
        data.params.unbacked = reserveData.unbacked;
        data.params.totalStableDebt = reserveData.totalStableDebt;
        data.params.totalVariableDebt = reserveData.totalVariableDebt;
        data.params.averageStableBorrowRate = reserveData.averageStableBorrowRate;
        (,,,, data.params.reserveFactor,,,,,) = _dataProvider.getReserveConfigurationData(address(asset));
        data.params.reserve = address(asset);
        IPoolDataProviderV31 dataV31 = IPoolDataProviderV31(address(_dataProvider));
        data.params.usingVirtualBalance = dataV31.getIsVirtualAccActive(address(asset));
        data.params.virtualUnderlyingBalance = dataV31.getVirtualUnderlyingBalance(address(asset));
    }

    // Visible so we can decode using wagmi
    function collectIrmDataV2V3(IERC20 asset) public view virtual returns (IRMData memory data) {
        IPoolDataProviderV3 _dataProvider = dataProvider();
        {
            IPoolDataProviderV3.ReserveData memory reserveData = _dataProvider.getReserveData(address(asset));
            data.unbacked = reserveData.unbacked;
            data.totalStableDebt = reserveData.totalStableDebt;
            data.totalVariableDebt = reserveData.totalVariableDebt;
            data.averageStableBorrowRate = reserveData.averageStableBorrowRate;
        }

        {
            (,,,, data.reserveFactor,,,,,) = _dataProvider.getReserveConfigurationData(address(asset));
        }
        {
            (address aTokenAddress,,) = _dataProvider.getReserveTokensAddresses(address(asset));
            data.aTokenReserveBalance = asset.balanceOf(aTokenAddress);
        }

        {
            IDefaultReserveInterestRateStrategyV3 irStrategy =
                IDefaultReserveInterestRateStrategyV3(_dataProvider.getInterestRateStrategyAddress(address(asset)));

            data.optimalUsageRatio = irStrategy.OPTIMAL_USAGE_RATIO();
            data.maxExcessUsageRatio = irStrategy.MAX_EXCESS_USAGE_RATIO();
            data.variableRateSlope1 = irStrategy.getVariableRateSlope1();
            data.variableRateSlope2 = irStrategy.getVariableRateSlope2();
            data.baseVariableBorrowRate = irStrategy.getBaseVariableBorrowRate();
        }
    }

    function _availableActions(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (AvailableActions[] memory available)
    {
        available = new AvailableActions[](ACTIONS);
        uint256 count;

        (bool baseActive, bool baseFrozen, bool basePaused, bool baseEnabled) = _reserveStatus(collateralAsset, false);
        if (baseActive && !baseFrozen && !basePaused && baseEnabled) available[count++] = AvailableActions.Lend;
        if (baseActive && !basePaused) available[count++] = AvailableActions.Withdraw;

        (bool quoteActive, bool quoteFrozen, bool quotePaused, bool quoteEnabled) = _reserveStatus(debtAsset, true);
        if (quoteActive && !quotePaused) available[count++] = AvailableActions.Repay;
        if (quoteActive && !quoteFrozen && !quotePaused && quoteEnabled) available[count++] = AvailableActions.Borrow;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(available, count)
        }
    }

    // ===== Internal Helper Functions =====

    function _reserveStatus(IERC20 asset, bool borrowing)
        internal
        view
        virtual
        returns (bool isActive, bool isFrozen, bool isPaused, bool enabled)
    {
        bool usageAsCollateralEnabled;
        bool borrowingEnabled;
        (,,,,, usageAsCollateralEnabled, borrowingEnabled,, isActive, isFrozen) = dataProvider().getReserveConfigurationData(address(asset));
        enabled = borrowing ? borrowingEnabled : usageAsCollateralEnabled;

        isPaused = dataProvider().getPaused(address(asset));
    }

    function _borrowingLiquidity(IERC20 asset) internal view virtual returns (uint256 borrowingLiquidity_) {
        (uint256 borrowCap,) = dataProvider().getReserveCaps(address(asset));
        borrowCap = borrowCap * 10 ** asset.decimals();
        uint256 totalDebt = dataProvider().getTotalDebt(address(asset));

        uint256 maxBorrowable = borrowCap > totalDebt ? borrowCap - totalDebt : 0;
        (address aTokenAddress,,) = dataProvider().getReserveTokensAddresses(address(asset));
        uint256 available;
        // GHO is a bit different
        if (MM_AAVE == moneyMarketId && block.chainid == 1 && address(asset) == 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f) {
            available = maxBorrowable;
        } else {
            available = asset.balanceOf(aTokenAddress);
        }

        borrowingLiquidity_ = borrowCap == 0 ? available : Math.min(maxBorrowable, available);
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual returns (uint256 lendingLiquidity_) {
        (uint256 decimals,,,,,,,,,) = dataProvider().getReserveConfigurationData(address(asset));

        (, uint256 supplyCap) = dataProvider().getReserveCaps(address(asset));
        if (supplyCap == 0) return asset.totalSupply(); // Infinite supply cap

        supplyCap = supplyCap * 10 ** decimals;
        uint256 currentSupply = _getTokenSupply(asset, false);

        lendingLiquidity_ = supplyCap > currentSupply ? supplyCap - currentSupply : 0;
    }

    struct RewardRawData {
        TokenData rewardToken;
        uint256 claimable;
        uint256 distributionEnd;
        uint256 emissionsPerSecond;
        uint256 tokenSupply;
        uint256 tokenPrice;
    }

    // Visible so we can decode using wagmi
    function rawRewardData(address account, IERC20 underlying, bool borrowing) public view returns (RewardRawData[] memory data) {
        if (rewardsController == IAaveRewardsController(address(0))) return data;

        (address aTokenAddress,, address variableDebtTokenAddress) = dataProvider().getReserveTokensAddresses(address(underlying));
        address asset = borrowing ? variableDebtTokenAddress : aTokenAddress;

        address[] memory rewardTokens = rewardsController.getRewardsByAsset(asset);
        data = new RewardRawData[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20 rewardToken = IERC20(rewardTokens[i]);
            IAaveRewardsController.RewardsData memory rewardsData = rewardsController.getRewardsData(asset, rewardTokens[i]);
            data[i].rewardToken = _asTokenData(rewardToken);
            data[i].claimable = account != address(0) ? rewardsController.getUserRewards(toArray(asset), account, rewardTokens[i]) : 0;
            data[i].distributionEnd = rewardsData.distributionEnd;
            data[i].emissionsPerSecond = rewardsData.emissionsPerSecond;
            data[i].tokenSupply = _getTokenSupply(underlying, borrowing);
            data[i].tokenPrice = oracle().getAssetPrice(underlying);
        }
    }

    function _asRewards(address account, IERC20 underlying, bool borrowing) internal view returns (Reward[] memory rewards_) {
        (address aTokenAddress,, address variableDebtTokenAddress) = dataProvider().getReserveTokensAddresses(address(underlying));
        address asset = borrowing ? variableDebtTokenAddress : aTokenAddress;

        address[] memory rewardTokens = rewardsController.getRewardsByAsset(asset);
        rewards_ = new Reward[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            IERC20 rewardToken = IERC20(rewardTokens[i]);
            IAaveRewardsController.RewardsData memory data = rewardsController.getRewardsData(asset, rewardTokens[i]);
            rewards_[i].claimable = account != address(0) ? rewardsController.getUserRewards(toArray(asset), account, rewardTokens[i]) : 0;
            rewards_[i].token = _asTokenData(rewardToken);
            {
                IAggregatorV2V3 rewardOracle = rewardsController.getRewardOracle(rewardToken);
                rewards_[i].usdPrice = uint256(rewardOracle.latestAnswer()) * 1e18 / 10 ** rewardOracle.decimals();
            }

            if (block.timestamp > data.distributionEnd) continue;

            rewards_[i].rate = _getIncentiveRate({
                tokenSupply: _getTokenSupply(underlying, borrowing),
                emissionsPerSecond: data.emissionsPerSecond,
                priceShares: rewards_[i].usdPrice,
                tokenPrice: oracle().getAssetPrice(underlying),
                decimals: underlying.decimals(),
                precisionAdjustment: 1e10
            });
        }
    }

    function _getTokenSupply(IERC20 asset, bool borrowing) internal view virtual returns (uint256 tokenSupply) {
        if (borrowing) {
            return dataProvider().getReserveData(address(asset)).totalVariableDebt;
        } else {
            AaveDataTypes.ReserveData memory reserve = pool().getReserveData(asset);
            return (reserve.aTokenAddress.scaledTotalSupply() + reserve.accruedToTreasury).mulDiv(
                pool().getReserveNormalizedIncome(asset), RAY
            );
        }
    }

    function _getIncentiveRate(
        uint256 tokenSupply,
        uint256 emissionsPerSecond,
        uint256 priceShares,
        uint256 tokenPrice,
        uint8 decimals,
        uint256 precisionAdjustment
    ) internal pure virtual returns (uint256) {
        uint256 emissionPerYear = emissionsPerSecond * 365 days;
        uint256 totalSupplyInUsd = tokenSupply * tokenPrice / (10 ** decimals);
        uint256 apr = totalSupplyInUsd != 0 ? priceShares * emissionPerYear / totalSupplyInUsd : 0;
        // Adjust decimals
        return apr / precisionAdjustment;
    }

    function pool() public view virtual returns (IPool) {
        return poolAddressesProvider.getPool();
    }

    function dataProvider() public view virtual returns (IPoolDataProviderV3) {
        return poolAddressesProvider.getPoolDataProvider();
    }

    function oracle() public view virtual returns (IAaveOracle) {
        return poolAddressesProvider.getPriceOracle();
    }

}

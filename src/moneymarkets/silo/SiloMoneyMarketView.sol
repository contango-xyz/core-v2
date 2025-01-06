//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../dependencies/Chainlink.sol";
import "../../libraries/Arrays.sol";

import "./SiloBase.sol";
import "../BaseMoneyMarketView.sol";

contract SiloMoneyMarketView is BaseMoneyMarketView, SiloBase {

    using Math for *;
    using { isCollateralOnly } for PositionId;

    struct PauseStatus {
        bool global;
        bool collateral;
        bool debt;
    }

    ISiloPriceProvidersRepository public immutable priceProvidersRepository;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        ISiloLens _lens,
        ISilo _wstEthSilo,
        IERC20 _stablecoin
    )
        BaseMoneyMarketView(_moneyMarketId, "Silo", _contango, _nativeToken, _nativeUsdOracle)
        SiloBase(_lens, _wstEthSilo, _nativeToken, _stablecoin)
    {
        priceProvidersRepository = repository.priceProvidersRepository();
    }

    // ====== IMoneyMarketView =======

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        ISilo silo = getSilo(collateralAsset, debtAsset);
        PauseStatus memory pauseStatus = _pauseStatus(silo, collateralAsset, debtAsset);
        if (!(pauseStatus.global || pauseStatus.collateral)) silo.accrueInterest(collateralAsset);
        if (!(pauseStatus.global || pauseStatus.debt)) silo.accrueInterest(debtAsset);
        balances_.collateral = lens.collateralBalanceOfUnderlying(silo, collateralAsset, account);
        balances_.debt = lens.getBorrowAmount(silo, debtAsset, account, block.timestamp);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return 10 ** priceProvidersRepository.QUOTE_TOKEN_DECIMALS();
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        try priceProvidersRepository.getPrice(asset) returns (uint256 price) {
            return price;
        } catch {
            return 0;
        }
    }

    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) {
        return _oraclePrice(asset);
    }

    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) {
        return _oraclePrice(asset) * uint256(nativeUsdOracle.latestAnswer()) / 1e8;
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        ISiloRepository.AssetConfig memory assetConfig = repository.assetConfigs(getSilo(collateralAsset, debtAsset), collateralAsset);
        ltv = assetConfig.maxLoanToValue;
        liquidationThreshold = assetConfig.liquidationThreshold;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        ISilo silo = getSilo(collateralAsset, debtAsset);
        borrowing = lens.liquidity(silo, debtAsset);

        uint256 maxDepositValue = repository.getMaxSiloDepositsValue(silo, collateralAsset);
        if (maxDepositValue == type(uint256).max) {
            lending = collateralAsset.totalSupply();
        } else {
            ISilo.AssetStorage memory assetState = silo.assetStorage(collateralAsset);
            uint256 price = priceProvidersRepository.getPrice(collateralAsset);
            uint256 deposits = assetState.totalDeposits + assetState.collateralOnlyDeposits;
            uint256 unit = 10 ** collateralAsset.decimals();
            uint256 depositsValue = deposits * price / unit;
            if (depositsValue > maxDepositValue) lending = 0;
            else lending = (maxDepositValue - depositsValue) * unit / price;
        }
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    { }

    function _irmRaw(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (bytes memory data)
    {
        data = abi.encode(rawData(positionId, collateralAsset, debtAsset));
    }

    struct RawData {
        bool paused;
        SiloData collateralData;
        SiloData debtData;
        uint256 userUnclaimedRewards;
    }

    struct SiloData {
        ISilo.UtilizationData utilizationData;
        IInterestRateModelV2.Config irmConfig;
        uint256 protocolShareFee;
        ISilo.AssetInterestData assetInterestData;
        ISilo.AssetStorage assetStorage;
        RewardData rewardData;
        bool paused;
    }

    struct RewardData {
        IERC20 siloAsset;
        TokenData rewardToken;
        ISiloIncentivesController.AssetData assetData;
        uint256 claimable;
    }

    function rawData(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) public view returns (RawData memory data) {
        ISilo silo = getSilo(collateralAsset, debtAsset);
        ISiloIncentivesController incentivesController = repository.getNotificationReceiver(silo);
        return RawData({
            paused: repository.isPaused(),
            collateralData: _collectSiloData(positionId, silo, incentivesController, collateralAsset, true),
            debtData: _collectSiloData(positionId, silo, incentivesController, debtAsset, false),
            userUnclaimedRewards: _userUnclaimedRewards(positionId, incentivesController)
        });
    }

    function _collectSiloData(PositionId positionId, ISilo silo, ISiloIncentivesController incentivesController, IERC20 asset, bool lending)
        internal
        view
        virtual
        returns (SiloData memory data)
    {
        data.utilizationData = silo.utilizationData(asset);
        data.irmConfig = repository.getInterestRateModel(silo, asset).getConfig(silo, asset);
        data.protocolShareFee = repository.protocolShareFee();
        data.assetInterestData = silo.interestData(asset);
        data.paused = repository.isSiloPaused(silo, asset);
        data.assetStorage = silo.assetStorage(asset);

        if (address(incentivesController) != address(0)) {
            IERC20 siloAsset = lending
                ? positionId.isCollateralOnly() ? data.assetStorage.collateralOnlyToken : data.assetStorage.collateralToken
                : data.assetStorage.debtToken;

            data.rewardData = RewardData({
                siloAsset: siloAsset,
                rewardToken: _asTokenData(incentivesController.REWARD_TOKEN()),
                claimable: incentivesController.getRewardsBalance(toArray(siloAsset), _account(positionId)),
                assetData: incentivesController.getAssetData(siloAsset)
            });
        }
    }

    function _userUnclaimedRewards(PositionId positionId, ISiloIncentivesController incentivesController)
        internal
        view
        returns (uint256 userUnclaimedRewards)
    {
        if (address(incentivesController) != address(0)) {
            userUnclaimedRewards = incentivesController.getUserUnclaimedRewards(_account(positionId));
        }
    }

    function _availableActions(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (AvailableActions[] memory available)
    {
        ISilo silo = getSilo(collateralAsset, debtAsset);

        available = new AvailableActions[](ACTIONS);
        uint256 count;

        PauseStatus memory pauseStatus = _pauseStatus(silo, collateralAsset, debtAsset);
        if (!pauseStatus.global) {
            if (!pauseStatus.collateral && silo.interestData(collateralAsset).status == ISilo.AssetStatus.Active) {
                available[count++] = AvailableActions.Lend;
                available[count++] = AvailableActions.Withdraw;
            }

            if (!pauseStatus.debt && silo.interestData(debtAsset).status == ISilo.AssetStatus.Active) {
                available[count++] = AvailableActions.Borrow;
                available[count++] = AvailableActions.Repay;
            }
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(available, count)
        }
    }

    function _pauseStatus(ISilo silo, IERC20 collateralAsset, IERC20 debtAsset) internal view returns (PauseStatus memory pauseStatus) {
        pauseStatus.global = repository.isPaused();
        pauseStatus.collateral = repository.isSiloPaused(silo, collateralAsset);
        pauseStatus.debt = repository.isSiloPaused(silo, debtAsset);
    }

}

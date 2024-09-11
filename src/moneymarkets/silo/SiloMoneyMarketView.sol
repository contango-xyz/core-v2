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

    struct IRMData {
        ISilo.UtilizationData utilizationData;
        IInterestRateModelV2.Config irmConfig;
        uint256 protocolShareFee;
    }

    struct PauseStatus {
        bool global;
        bool collateral;
        bool debt;
    }

    error OracleBaseCurrencyNotUSD();

    ISiloPriceProvidersRepository public immutable priceProvidersRepository;

    constructor(
        MoneyMarketId _moneyMarketId,
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        ISiloLens _lens,
        ISiloIncentivesController _incentivesController,
        ISilo _wstEthSilo,
        IERC20 _stablecoin
    )
        BaseMoneyMarketView(_moneyMarketId, "Silo", _contango, _nativeToken, _nativeUsdOracle)
        SiloBase(_lens, _incentivesController, _wstEthSilo, _nativeToken, _stablecoin)
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
    {
        ISilo silo = getSilo(collateralAsset, debtAsset);
        borrowing = lens.borrowAPY(silo, debtAsset);
        lending = lens.depositAPY(silo, collateralAsset);
    }

    function _irmRaw(PositionId, IERC20 collateralAsset, IERC20 debtAsset) internal view virtual override returns (bytes memory data) {
        ISilo silo = getSilo(collateralAsset, debtAsset);
        data = abi.encode(_collectIrmData(silo, collateralAsset), _collectIrmData(silo, debtAsset));
    }

    function _collectIrmData(ISilo silo, IERC20 asset) internal view virtual returns (IRMData memory data) {
        data.utilizationData = silo.utilizationData(asset);
        data.irmConfig = repository.getInterestRateModel(silo, asset).getConfig(silo, asset);
        data.protocolShareFee = repository.protocolShareFee();
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        ISilo silo = getSilo(collateralAsset, debtAsset);
        borrowing = _asRewards({ positionId: positionId, silo: silo, asset: debtAsset, lending: false });
        lending = _asRewards({ positionId: positionId, silo: silo, asset: collateralAsset, lending: true });
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

    // ===== Internal Helper Functions =====

    function _pauseStatus(ISilo silo, IERC20 collateralAsset, IERC20 debtAsset) internal view returns (PauseStatus memory pauseStatus) {
        pauseStatus.global = repository.isPaused();
        pauseStatus.collateral = repository.isSiloPaused(silo, collateralAsset);
        pauseStatus.debt = repository.isSiloPaused(silo, debtAsset);
    }

    function _asRewards(PositionId positionId, ISilo silo, IERC20 asset, bool lending) internal view returns (Reward[] memory rewards_) {
        IERC20 siloAsset = lending
            ? positionId.isCollateralOnly() ? silo.assetStorage(asset).collateralOnlyToken : silo.assetStorage(asset).collateralToken
            : silo.assetStorage(asset).debtToken;

        uint256 claimable = incentivesController.getRewardsBalance(toArray(siloAsset), _account(positionId));
        uint256 emissionPerSecond = incentivesController.getAssetData(siloAsset).emissionPerSecond;

        if (emissionPerSecond == 0 && claimable == 0) return new Reward[](0);

        rewards_ = new Reward[](1);

        IERC20 rewardsToken = incentivesController.REWARD_TOKEN();

        rewards_[0].usdPrice = priceInUSD(rewardsToken);
        rewards_[0].token = _asTokenData(rewardsToken);
        rewards_[0].claimable = claimable;

        uint256 valueOfEmissions = emissionPerSecond * rewards_[0].usdPrice / WAD;
        uint256 assetPrice = priceInUSD(asset);

        uint256 totalAmount = lending
            ? positionId.isCollateralOnly() ? silo.assetStorage(asset).collateralOnlyDeposits : silo.assetStorage(asset).totalDeposits
            : silo.assetStorage(asset).totalBorrowAmount;

        uint256 valueOfAssets = assetPrice * totalAmount / 10 ** asset.decimals();
        rewards_[0].rate = _apy({ rate: valueOfEmissions * WAD / valueOfAssets, perSeconds: 1 });
    }

}

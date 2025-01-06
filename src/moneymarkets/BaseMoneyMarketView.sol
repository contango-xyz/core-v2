//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import { UD60x18, ud, UNIT } from "@prb/math/src/UD60x18.sol";

import { IAggregatorV2V3 } from "../dependencies/Chainlink.sol";
import "../dependencies/IPauseable.sol";
import "../interfaces/IContango.sol";
import "./interfaces/IMoneyMarketView.sol";

abstract contract BaseMoneyMarketView is IMoneyMarketView {

    UD60x18 internal constant DAYS_PER_YEAR = UD60x18.wrap(365e18);
    UD60x18 internal constant SECONDS_PER_DAY = UD60x18.wrap(1 days * WAD);
    uint256 internal constant ACTIONS = uint256(type(AvailableActions).max) + 1;

    MoneyMarketId public immutable override moneyMarketId;
    string public override moneyMarketName;
    IContango public immutable contango;
    IUnderlyingPositionFactory public immutable positionFactory;
    IWETH9 public immutable nativeToken;
    IAggregatorV2V3 public immutable nativeUsdOracle;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) {
        moneyMarketId = _moneyMarketId;
        moneyMarketName = _moneyMarketName;
        contango = _contango;
        positionFactory = _contango.positionFactory();
        nativeToken = _nativeToken;
        nativeUsdOracle = _nativeUsdOracle;
    }

    function balances(PositionId positionId) public override returns (Balances memory balances_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _balances(positionId, collateralAsset, debtAsset);
    }

    function balancesUSD(PositionId positionId) public override returns (Balances memory balances_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        balances_ = _balances(positionId, collateralAsset, debtAsset);
        balances_.collateral = balances_.collateral * priceInUSD(collateralAsset) / 10 ** collateralAsset.decimals();
        balances_.debt = balances_.debt * priceInUSD(debtAsset) / 10 ** debtAsset.decimals();
    }

    function prices(PositionId positionId) public view override returns (Prices memory prices_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _prices(positionId, collateralAsset, debtAsset);
    }

    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) {
        uint256 nativeTokenDecimals = nativeToken.decimals();
        uint256 nativeTokenUnit = 10 ** nativeTokenDecimals;
        if (asset == nativeToken) return nativeTokenUnit;

        uint256 assetPrice = _oraclePrice(asset);
        uint256 nativeAssetPrice = _oraclePrice(nativeToken);

        return assetPrice * nativeTokenUnit / nativeAssetPrice;
    }

    function _derivePriceInUSD(IERC20 asset) internal view returns (uint256 price_) {
        if (asset == nativeToken) return uint256(nativeUsdOracle.latestAnswer()) * 1e10;
        return priceInNativeToken(asset) * uint256(nativeUsdOracle.latestAnswer()) / 1e8;
    }

    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) {
        // Most money markets use USD as the quote asset, so we can use the oracle directly.
        return _oraclePrice(asset) * WAD / _oracleUnit();
    }

    function baseQuoteRate(PositionId positionId) external view virtual override returns (uint256 rate_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        Prices memory __prices = _prices(positionId, collateralAsset, debtAsset);
        rate_ = __prices.collateral * 10 ** debtAsset.decimals() / __prices.debt;
    }

    function thresholds(PositionId positionId) public view override returns (uint256 ltv, uint256 liquidationThreshold) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _thresholds(positionId, collateralAsset, debtAsset);
    }

    function liquidity(PositionId positionId) public view override returns (uint256 borrowing, uint256 lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _liquidity(positionId, collateralAsset, debtAsset);
    }

    function rates(PositionId positionId) public view override returns (uint256 borrowing, uint256 lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _rates(positionId, collateralAsset, debtAsset);
    }

    function irmRaw(PositionId positionId) external override returns (bytes memory data) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _irmRaw(positionId, collateralAsset, debtAsset);
    }

    function rewards(PositionId positionId) public override returns (Reward[] memory borrowing, Reward[] memory lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _rewards(positionId, collateralAsset, debtAsset);
    }

    function availableActions(PositionId positionId) public override returns (AvailableActions[] memory available) {
        if (IPauseable(address(contango)).paused()) return available;

        Instrument memory instrument = contango.instrument(positionId.getSymbol());
        available = _availableActions(positionId, instrument.base, instrument.quote);
        if (instrument.closingOnly) {
            AvailableActions[] memory _available = new AvailableActions[](available.length);
            uint256 j;
            for (uint256 i; i < available.length; i++) {
                if (available[i] != AvailableActions.Lend && available[i] != AvailableActions.Borrow) _available[j++] = available[i];
            }
            available = _available;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                mstore(available, j)
            }
        }
    }

    function limits(PositionId positionId) external view override returns (Limits memory limits_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _limits(positionId, collateralAsset, debtAsset);
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        returns (Balances memory balances_)
    {
        if (positionId.getNumber() > 0) {
            IMoneyMarket mm = IMoneyMarket(_account(positionId));
            balances_.collateral = mm.collateralBalance(positionId, collateralAsset);
            balances_.debt = mm.debtBalance(positionId, debtAsset);
        }
    }

    function _prices(PositionId, IERC20 collateralAsset, IERC20 debtAsset) internal view virtual returns (Prices memory prices_) {
        prices_.collateral = _oraclePrice(collateralAsset);
        prices_.debt = _oraclePrice(debtAsset);
        prices_.unit = _oracleUnit();
    }

    function _thresholds(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        returns (uint256 ltv, uint256 liquidationThreshold);

    function _liquidity(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        returns (uint256 borrowing, uint256 lending);

    function _rates(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        returns (uint256 borrowing, uint256 lending);

    function _irmRaw(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual returns (bytes memory data) { }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        returns (Reward[] memory borrowing, Reward[] memory lending)
    { }

    function _assets(PositionId positionId) internal view virtual returns (IERC20 collateralAsset, IERC20 debtAsset) {
        Instrument memory instrument = contango.instrument(positionId.getSymbol());
        collateralAsset = instrument.base;
        debtAsset = instrument.quote;
    }

    function _account(PositionId positionId) internal view virtual returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

    function _apy(uint256 rate, uint256 perSeconds) internal pure returns (uint256) {
        UD60x18 _rate = ud(rate) / ud(perSeconds * WAD) * SECONDS_PER_DAY;

        // APY = (rate + 1) ^ Days Per Year - 1)
        return ((_rate + UNIT).pow(DAYS_PER_YEAR) - UNIT).unwrap();
    }

    function _asTokenData(IERC20 token) internal view returns (TokenData memory tokenData_) {
        uint8 decimals = token.decimals();
        tokenData_.token = token;
        tokenData_.name = token.name();
        tokenData_.symbol = token.symbol();
        tokenData_.decimals = decimals;
        tokenData_.unit = 10 ** decimals;
    }

    function _oraclePrice(IERC20 asset) internal view virtual returns (uint256);

    function _oracleUnit() internal view virtual returns (uint256);

    function _availableActions(PositionId, IERC20, IERC20) internal virtual returns (AvailableActions[] memory available) {
        available = new AvailableActions[](ACTIONS);
        available[0] = AvailableActions.Lend;
        available[1] = AvailableActions.Withdraw;
        available[2] = AvailableActions.Borrow;
        available[3] = AvailableActions.Repay;
    }

    function _limits(PositionId, IERC20, IERC20) internal view virtual returns (Limits memory limits_) {
        limits_.minBorrowing = limits_.minLending = limits_.minBorrowingForRewards = limits_.minLendingForRewards = 0;
        limits_.maxBorrowing = limits_.maxLending = type(uint256).max;
    }

}

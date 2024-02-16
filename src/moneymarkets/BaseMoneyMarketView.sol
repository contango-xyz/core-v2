//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IAggregatorV2V3 } from "../dependencies/Chainlink.sol";
import "../interfaces/IContango.sol";
import "./interfaces/IMoneyMarketView.sol";

abstract contract BaseMoneyMarketView is IMoneyMarketView {

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

    function balances(PositionId positionId) public virtual returns (Balances memory balances_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _balances(positionId, collateralAsset, debtAsset);
    }

    function prices(PositionId positionId) public view virtual override returns (Prices memory prices_) {
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

    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) {
        if (asset == nativeToken) return uint256(nativeUsdOracle.latestAnswer()) * 1e10;
        return priceInNativeToken(asset) * uint256(nativeUsdOracle.latestAnswer()) / 1e8;
    }

    function baseQuoteRate(PositionId positionId) external view virtual override returns (uint256 rate_) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        Prices memory __prices = _prices(positionId, collateralAsset, debtAsset);
        rate_ = __prices.collateral * 10 ** debtAsset.decimals() / __prices.debt;
    }

    function thresholds(PositionId positionId) public view virtual override returns (uint256 ltv, uint256 liquidationThreshold) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _thresholds(positionId, collateralAsset, debtAsset);
    }

    function liquidity(PositionId positionId) public view virtual override returns (uint256 borrowing, uint256 lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _liquidity(positionId, collateralAsset, debtAsset);
    }

    function rates(PositionId positionId) public view virtual override returns (uint256 borrowing, uint256 lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _rates(positionId, collateralAsset, debtAsset);
    }

    function rewards(PositionId positionId) public virtual override returns (Reward[] memory borrowing, Reward[] memory lending) {
        (IERC20 collateralAsset, IERC20 debtAsset) = _assets(positionId);
        return _rewards(positionId, collateralAsset, debtAsset);
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        returns (Balances memory balances_);

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

    function _oraclePrice(IERC20 asset) internal view virtual returns (uint256);

    function _oracleUnit() internal view virtual returns (uint256);

}

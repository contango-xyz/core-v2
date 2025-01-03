//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IMorpho.sol";
import { SharesMathLib } from "./dependencies/SharesMathLib.sol";

import "../BaseMoneyMarketView.sol";
import "./MorphoBlueReverseLookup.sol";

contract MorphoBlueMoneyMarketView is BaseMoneyMarketView {

    using Math for *;
    using SharesMathLib for *;

    struct IRMData {
        uint128 totalSupplyAssets;
        uint128 totalBorrowAssets;
        uint128 lastUpdate;
        int256 rateAtTarget;
    }

    error OracleNotFound(IERC20 asset);

    uint256 public constant ORACLE_PRICE_DECIMALS = 36;

    IMorpho public immutable morpho;
    MorphoBlueReverseLookup public immutable reverseLookup;
    IERC20 public immutable ena;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        IMorpho _morpho,
        MorphoBlueReverseLookup _reverseLookup,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        IERC20 _ena
    ) BaseMoneyMarketView(_moneyMarketId, _moneyMarketName, _contango, _nativeToken, _nativeUsdOracle) {
        morpho = _morpho;
        reverseLookup = _reverseLookup;
        ena = _ena;
    }

    // ====== IMoneyMarketView =======

    function _balances(PositionId positionId, IERC20, IERC20) internal virtual override returns (Balances memory balances_) {
        MorphoMarketId marketId = reverseLookup.marketId(positionId.getPayload());
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        morpho.accrueInterest(marketParams); // Accrue interest before before loading the market state
        Market memory market = morpho.market(marketId);
        Position memory position = morpho.position(marketId, _account(positionId));
        balances_.collateral = position.collateral;
        balances_.debt = position.borrowShares.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
    }

    function _prices(PositionId positionId, IERC20, IERC20) internal view virtual override returns (Prices memory prices_) {
        MarketParams memory params = morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload()));

        uint256 priceDecimals = ORACLE_PRICE_DECIMALS + params.loanToken.decimals() - params.collateralToken.decimals();

        prices_.collateral = params.oracle.price();
        prices_.debt = prices_.unit = 10 ** priceDecimals;
    }

    function _thresholds(PositionId positionId, IERC20, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        ltv = liquidationThreshold = morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload())).lltv;
    }

    function _liquidity(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        Market memory market = morpho.market(reverseLookup.marketId(positionId.getPayload()));
        borrowing = market.totalSupplyAssets - market.totalBorrowAssets;
        lending = collateralAsset.totalSupply();
    }

    function _rates(PositionId positionId, IERC20, IERC20) internal view virtual override returns (uint256 borrowing, uint256 lending) {
        MorphoMarketId marketId = reverseLookup.marketId(positionId.getPayload());
        MarketParams memory params = morpho.idToMarketParams(marketId);

        borrowing = _apy({ rate: params.irm.borrowRateView(params, morpho.market(marketId)), perSeconds: 1 });
        lending = 0;
    }

    function _irmRaw(PositionId positionId, IERC20, IERC20) internal view virtual override returns (bytes memory data) {
        MorphoMarketId marketId = reverseLookup.marketId(positionId.getPayload());
        Market memory market = morpho.market(marketId);
        MarketParams memory params = morpho.idToMarketParams(marketId);

        return abi.encode(
            IRMData({
                totalSupplyAssets: market.totalSupplyAssets,
                totalBorrowAssets: market.totalBorrowAssets,
                lastUpdate: market.lastUpdate,
                rateAtTarget: params.irm.rateAtTarget(marketId)
            })
        );
    }

    // So these functions can't be implemented
    // The reason why they are not made to revert is because Solidity would thrown an "Unreachable code" error
    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) { }
    function _oracleUnit() internal view virtual override returns (uint256) { }
    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) { }
    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) { }

}

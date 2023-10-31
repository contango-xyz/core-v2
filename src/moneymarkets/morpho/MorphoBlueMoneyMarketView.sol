//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IMorpho.sol";
import { SharesMathLib } from "./dependencies/SharesMathLib.sol";

import "../interfaces/IMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";
import "./MorphoBlueReverseLookup.sol";

contract MorphoBlueMoneyMarketView is IMoneyMarketView {

    error OracleBaseCurrencyNotUSD();

    using Math for *;
    using SharesMathLib for uint256;

    uint256 public constant ORACLE_PRICE_DECIMALS = 36;

    MoneyMarketId public immutable override moneyMarketId;
    IUnderlyingPositionFactory public immutable positionFactory;
    IMorpho public immutable morpho;
    MorphoBlueReverseLookup public immutable reverseLookup;

    constructor(
        MoneyMarketId _moneyMarketId,
        IUnderlyingPositionFactory _positionFactory,
        IMorpho _morpho,
        MorphoBlueReverseLookup _reverseLookup
    ) {
        moneyMarketId = _moneyMarketId;
        positionFactory = _positionFactory;
        morpho = _morpho;
        reverseLookup = _reverseLookup;
    }

    // ====== IMoneyMarketView =======

    function balances(PositionId positionId, IERC20, IERC20) public virtual override returns (Balances memory balances_) {
        Id marketId = reverseLookup.marketId(positionId.getPayload());
        MarketParams memory marketParams = morpho.idToMarketParams(marketId);
        morpho.accrueInterest(marketParams); // Accrue interest before before loading the market state
        Market memory market = morpho.market(marketId);
        (, balances_.debt, balances_.collateral) = morpho.position(marketId, _account(positionId));
        balances_.debt = balances_.debt.toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
    }

    function prices(PositionId positionId, IERC20, IERC20) public view virtual override returns (Prices memory prices_) {
        MarketParams memory params = morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload()));

        uint256 priceDecimals = ORACLE_PRICE_DECIMALS + params.loanToken.decimals() - params.collateralToken.decimals();

        prices_.collateral = params.oracle.price();
        prices_.unit = 10 ** priceDecimals;
        prices_.debt = prices_.unit;
    }

    function thresholds(PositionId positionId, IERC20, IERC20)
        public
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        ltv = liquidationThreshold = morpho.idToMarketParams(reverseLookup.marketId(positionId.getPayload())).lltv;
    }

    function liquidity(PositionId positionId, IERC20 collateralAsset, IERC20)
        public
        view
        virtual
        returns (uint256 borrowing, uint256 lending)
    {
        Market memory market = morpho.market(reverseLookup.marketId(positionId.getPayload()));
        borrowing = market.totalSupplyAssets - market.totalBorrowAssets;
        lending = collateralAsset.totalSupply();
    }

    function rates(PositionId positionId, IERC20, IERC20) public view virtual returns (uint256 borrowing, uint256 lending) {
        Id marketId = reverseLookup.marketId(positionId.getPayload());
        MarketParams memory params = morpho.idToMarketParams(marketId);

        borrowing = params.irm.borrowRateView(params, morpho.market(marketId));
        lending = 0;
    }

    // ===== Internal Helper Functions =====

    function _account(PositionId positionId) internal view returns (address) {
        return address(positionFactory.moneyMarket(positionId));
    }

}

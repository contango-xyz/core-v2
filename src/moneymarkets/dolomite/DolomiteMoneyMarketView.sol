//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IDolomiteMargin.sol";
import "./DolomiteMoneyMarket.sol";

import "../BaseMoneyMarketView.sol";
import { MM_DOLOMITE } from "script/constants.sol";

contract DolomiteMoneyMarketView is BaseMoneyMarketView {

    using Math for *;

    enum IRM {
        Linear,
        AaveCopyCat,
        AlwaysZero
    }

    struct IRMData {
        uint256 borrowWei;
        uint256 supplyWei;
        uint256 lowerOptimalPercent;
        uint256 upperOptimalPercent;
        uint256 earningsRate;
        IRM irm;
    }

    IDolomiteMargin public immutable dolomite;

    constructor(IContango _contango, IWETH9 _nativeToken, IAggregatorV2V3 _nativeUsdOracle, IDolomiteMargin _dolomite)
        BaseMoneyMarketView(MM_DOLOMITE, "Dolomite", _contango, _nativeToken, _nativeUsdOracle)
    {
        dolomite = _dolomite;
    }

    // ====== IMoneyMarketView =======

    function _assets(PositionId positionId) internal view override returns (IERC20 collateralAsset, IERC20 debtAsset) {
        uint256 marketId = uint40(Payload.unwrap(positionId.getPayload()));
        Instrument memory instrument = contango.instrument(positionId.getSymbol());
        collateralAsset = marketId > 0 ? dolomite.getMarketTokenAddress(marketId) : instrument.base;
        debtAsset = instrument.quote;
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        if (positionId.getNumber() > 0) {
            DolomiteMoneyMarket mm = DolomiteMoneyMarket(_account(positionId));
            balances_.collateral = mm.collateralBalance(positionId, collateralAsset);
            balances_.debt = mm.debtBalance(positionId, debtAsset);
        }
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return 1e8;
    }

    function _transformPrecision(uint256 x, uint256 from, uint256 to) internal pure virtual returns (uint256) {
        if (to > from) return x * 10 ** (to - from);
        else return x / 10 ** (from - to);
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        try dolomite.getMarketIdByTokenAddress(asset) returns (uint256 marketId) {
            return _transformPrecision(dolomite.getMarketPrice(marketId).value, 36 - asset.decimals(), 8);
        } catch {
            uint256 markets = dolomite.getNumMarkets();

            for (uint256 i = 0; i < markets; i++) {
                IIsolationToken token = IIsolationToken(address(dolomite.getMarketTokenAddress(i)));
                try token.UNDERLYING_TOKEN() returns (IERC20 underlying) {
                    if (underlying == asset) return _transformPrecision(dolomite.getMarketPrice(i).value, 36 - asset.decimals(), 8);
                } catch { }
            }

            revert UnsupportedAsset(asset);
        }
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        uint256 marginRatio = WAD + dolomite.getMarginRatio().value;
        uint256 collateralPremium = WAD + dolomite.getMarketMarginPremium(dolomite.getMarketIdByTokenAddress(collateralAsset)).value;
        uint256 debtPremium = WAD + dolomite.getMarketMarginPremium(dolomite.getMarketIdByTokenAddress(debtAsset)).value;

        uint256 totalPremium = collateralPremium.mulDiv(debtPremium, WAD, Math.Rounding.Up);

        marginRatio = marginRatio.mulDiv(totalPremium, WAD, Math.Rounding.Up);

        liquidationThreshold = ltv = Math.mulDiv(WAD, WAD, marginRatio);
    }

    function _marketTotals(IERC20 asset) internal view returns (uint256 supplyWei, uint256 borrowWei) {
        uint256 marketId = dolomite.getMarketIdByTokenAddress(asset);
        IDolomiteMargin.TotalPar memory par = dolomite.getMarketTotalPar(marketId);
        IDolomiteMargin.Index memory index = dolomite.getMarketCurrentIndex(marketId);
        supplyWei = Math.mulDiv(par.supply, index.supply, WAD);
        borrowWei = Math.mulDiv(par.borrow, index.borrow, WAD);
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        (uint256 supplyWei, uint256 borrowWei) = _marketTotals(debtAsset);
        borrowing = supplyWei > borrowWei ? supplyWei - borrowWei : 0;

        uint256 cap = dolomite.getMarketMaxWei(dolomite.getMarketIdByTokenAddress(collateralAsset)).value;
        if (cap == 0) {
            lending = collateralAsset.totalSupply();
        } else {
            (supplyWei,) = _marketTotals(collateralAsset);
            lending = cap > supplyWei ? cap - supplyWei : 0;
        }
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _apy({ rate: dolomite.getMarketInterestRate(dolomite.getMarketIdByTokenAddress(debtAsset)).value, perSeconds: 1 });

        uint256 collateralMarket = dolomite.getMarketIdByTokenAddress(collateralAsset);
        uint256 borrowRate = Math.mulDiv(dolomite.getMarketInterestRate(collateralMarket).value, dolomite.getEarningsRate().value, WAD);
        (uint256 supplyWei, uint256 borrowWei) = _marketTotals(collateralAsset);
        lending = _apy({ rate: Math.mulDiv(borrowRate, borrowWei, supplyWei), perSeconds: 1 });
    }

    function _irmRaw(PositionId, IERC20 collateralAsset, IERC20 debtAsset) internal view virtual override returns (bytes memory data) {
        data = abi.encode(_collectIrmData(collateralAsset), _collectIrmData(debtAsset));
    }

    function _collectIrmData(IERC20 asset) internal view returns (IRMData memory irm) {
        ILinearStepFunctionInterestSetter interestSetter = dolomite.getMarketInterestSetter(dolomite.getMarketIdByTokenAddress(asset));
        uint256 codeSize = address(interestSetter).code.length;
        if (codeSize < 1000) {
            irm.irm = IRM.AlwaysZero;
            return irm;
        }
        (irm.supplyWei, irm.borrowWei) = _marketTotals(asset);
        irm.earningsRate = dolomite.getEarningsRate().value;

        if (codeSize < 2000) {
            irm.irm = IRM.AaveCopyCat;
            return irm;
        }

        irm.irm = IRM.Linear;
        irm.lowerOptimalPercent = interestSetter.LOWER_OPTIMAL_PERCENT();
        irm.upperOptimalPercent = interestSetter.UPPER_OPTIMAL_PERCENT();
    }

    function _availableActions(PositionId, IERC20, IERC20 debtAsset) internal view override returns (AvailableActions[] memory available) {
        available = new AvailableActions[](ACTIONS);
        available[0] = AvailableActions.Lend;
        available[1] = AvailableActions.Withdraw;
        available[2] = AvailableActions.Repay;

        if (dolomite.getMarketIsClosing(dolomite.getMarketIdByTokenAddress(debtAsset))) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                mstore(available, 3)
            }
        } else {
            available[3] = AvailableActions.Borrow;
        }
    }

    function _limits(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Limits memory limits_)
    {
        limits_ = super._limits(positionId, collateralAsset, debtAsset);
        uint256 minBorrowingUSD = _transformPrecision(dolomite.getMinBorrowedValue().value, 36, 18);
        uint256 debtUSDPrice = priceInUSD(debtAsset);
        limits_.minBorrowing = Math.mulDiv(minBorrowingUSD, 10 ** debtAsset.decimals(), debtUSDPrice);
    }

    function __account(PositionId positionId) internal view returns (IDolomiteMargin.Info memory self) {
        self.owner = _account(positionId);
    }

}

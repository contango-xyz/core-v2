//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./AaveMoneyMarketView.sol";
import "./dependencies/Spark.sol";

contract SparkMoneyMarketView is AaveMoneyMarketView {

    IERC20 public immutable dai;
    ISDAI public immutable sDAI;
    IERC20 public immutable usdc;

    constructor(
        MoneyMarketId _moneyMarketId,
        IPoolAddressesProvider _provider,
        IUnderlyingPositionFactory _positionFactory,
        IERC20 _dai,
        ISDAI _sDAI,
        IERC20 _usdc
    ) AaveMoneyMarketView(_moneyMarketId, _provider, _positionFactory) {
        dai = _dai;
        sDAI = _sDAI;
        usdc = _usdc;
    }

    function balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        override
        returns (Balances memory balances_)
    {
        if (collateralAsset == dai || collateralAsset == usdc) {
            balances_ = super.balances(positionId, sDAI, debtAsset);
            balances_.collateral = sDAI.previewRedeem(balances_.collateral);
            if (collateralAsset == usdc) balances_.collateral /= 1e12;
        } else if (debtAsset == usdc) {
            balances_ = super.balances(positionId, collateralAsset, dai);
            balances_.debt = (balances_.debt + 1e12 - 1) / 1e12;
        } else {
            balances_ = super.balances(positionId, collateralAsset, debtAsset);
        }
    }

    function thresholds(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (ltv, liquidationThreshold) = (collateralAsset == dai || collateralAsset == usdc)
            ? super.thresholds(positionId, sDAI, debtAsset)
            : super.thresholds(positionId, collateralAsset, debtAsset);
    }

    function liquidity(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        bool lendingUSDC = collateralAsset == usdc;
        bool lendingSDAI = collateralAsset == dai || lendingUSDC;
        bool borrowingUSDC = debtAsset == usdc;

        (borrowing, lending) = super.liquidity(positionId, lendingSDAI ? sDAI : collateralAsset, borrowingUSDC ? dai : debtAsset);

        if (borrowingUSDC) borrowing = borrowing / 1e12;

        if (lendingSDAI) {
            if (lending < type(uint256).max) lending = sDAI.previewRedeem(lending);
            if (lendingUSDC) lending /= 1e12;
        }
    }

    function rates(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        public
        view
        override
        returns (uint256 borrowing, uint256 lending)
    {
        bool lendingUSDC = collateralAsset == usdc;
        bool lendingSDAI = collateralAsset == dai || lendingUSDC;
        bool borrowingUSDC = debtAsset == usdc;

        (borrowing, lending) = super.rates(positionId, collateralAsset, borrowingUSDC ? dai : debtAsset);

        if (lendingSDAI) lending = (_rpow(sDAI.pot().dsr(), 365 days) - RAY) / 1e9 + 1;
    }

    function _rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := RAY }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := RAY }
                default { z := x }
                let half := div(RAY, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, RAY)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, RAY)
                    }
                }
            }
        }
    }

}

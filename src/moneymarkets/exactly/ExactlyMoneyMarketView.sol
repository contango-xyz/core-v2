//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";

import "./dependencies/IAuditor.sol";
import "./dependencies/IExactlyPreviewer.sol";
import "./ExactlyReverseLookup.sol";

import "../BaseMoneyMarketView.sol";
import "../interfaces/IUnderlyingPositionFactory.sol";

contract ExactlyMoneyMarketView is BaseMoneyMarketView {

    using ERC20Lib for IERC20;
    using Math for uint256;
    using { find } for IExactlyPreviewer.ClaimableReward[];

    struct IRMData {
        uint256 floatingAssets;
        uint256 floatingDebt;
        uint256 floatingBackupBorrowed;
        uint256 floatingCurveA;
        int256 floatingCurveB;
        uint256 floatingMaxUtilization;
        int256 sigmoidSpeed;
        int256 growthSpeed;
        uint256 naturalUtilization;
        uint256 maxRate;
    }

    ExactlyReverseLookup public immutable reverseLookup;
    IAuditor public immutable auditor;
    IExactlyPreviewer public immutable previewer;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _name,
        IContango _contango,
        ExactlyReverseLookup _reverseLookup,
        IAuditor _auditor,
        IExactlyPreviewer _previewer,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) BaseMoneyMarketView(_moneyMarketId, _name, _contango, _nativeToken, _nativeUsdOracle) {
        reverseLookup = _reverseLookup;
        auditor = _auditor;
        previewer = _previewer;
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (Balances memory balances_)
    {
        IExactlyMarket collateralMarket = reverseLookup.market(collateralAsset);
        balances_.collateral = collateralMarket.convertToAssets(collateralMarket.balanceOf(_account(positionId)));
        balances_.debt = reverseLookup.market(debtAsset).previewDebt(_account(positionId));
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        return auditor.assetPrice(auditor.markets(reverseLookup.market(asset)).priceFeed);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return WAD;
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        uint256 collateralAdjustFactor = auditor.markets(reverseLookup.market(collateralAsset)).adjustFactor;
        uint256 debtAdjustFactor = auditor.markets(reverseLookup.market(debtAsset)).adjustFactor;

        liquidationThreshold = collateralAdjustFactor.mulDiv(debtAdjustFactor, WAD, Math.Rounding.Down);
        ltv = liquidationThreshold;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (uint256 borrowing, uint256 lending)
    {
        IExactlyMarket market = reverseLookup.market(debtAsset);
        uint256 adjusted = market.floatingAssets().mulDiv(WAD - market.reserveFactor(), WAD, Math.Rounding.Down);
        uint256 borrowed = market.floatingBackupBorrowed() + market.totalFloatingBorrowAssets();
        borrowing = adjusted > borrowed ? adjusted - borrowed : 0;

        lending = collateralAsset.totalSupply();
    }

    function _rates(PositionId, IERC20, IERC20 debtAsset) internal view override returns (uint256 borrowing, uint256 lending) {
        lending = 0;

        IExactlyMarket market = reverseLookup.market(debtAsset);
        borrowing = _apy({
            rate: market.interestRateModel().floatingRate(
                market.floatingAssets() > 0 ? Math.min(market.floatingDebt().mulDiv(WAD, market.floatingAssets(), Math.Rounding.Up), WAD) : 0
            ),
            perSeconds: 365 days
        });
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        IExactlyPreviewer.MarketAccount[] memory data = previewer.exactly(positionId.getNumber() > 0 ? _account(positionId) : address(0));
        for (uint256 i = 0; i < data.length; i++) {
            IExactlyPreviewer.MarketAccount memory marketAccount = data[i];
            if (marketAccount.asset == address(collateralAsset)) borrowing = _asRewards(marketAccount, false);
            if (marketAccount.asset == address(debtAsset)) lending = _asRewards(marketAccount, true);
        }
    }

    function _irmRaw(PositionId, IERC20, IERC20 debtAsset) internal view virtual override returns (bytes memory data) {
        IExactlyMarket market = reverseLookup.market(debtAsset);
        IInterestRateModel irm = market.interestRateModel();

        data = abi.encode(
            IRMData({
                floatingAssets: market.floatingAssets(),
                floatingDebt: market.floatingDebt(),
                floatingBackupBorrowed: market.floatingBackupBorrowed(),
                floatingCurveA: irm.floatingCurveA(),
                floatingCurveB: irm.floatingCurveB(),
                floatingMaxUtilization: irm.floatingMaxUtilization(),
                sigmoidSpeed: irm.sigmoidSpeed(),
                growthSpeed: irm.growthSpeed(),
                naturalUtilization: irm.naturalUtilization(),
                maxRate: irm.maxRate()
            })
        );
    }

    function _availableActions(PositionId, IERC20, IERC20 debtAsset) internal view override returns (AvailableActions[] memory available) {
        IExactlyMarket debtMarket = reverseLookup.market(debtAsset);

        available = new AvailableActions[](ACTIONS);
        uint256 count;

        available[count++] = AvailableActions.Lend;
        available[count++] = AvailableActions.Withdraw;

        if (!debtMarket.paused()) {
            available[count++] = AvailableActions.Borrow;
            available[count++] = AvailableActions.Repay;
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(available, count)
        }
    }

    // ===== Internal Helper Functions =====

    function _asRewards(IExactlyPreviewer.MarketAccount memory marketAccount, bool borrowing)
        internal
        view
        returns (Reward[] memory rewards_)
    {
        IExactlyPreviewer.RewardRate[] memory rewardRates = marketAccount.rewardRates;
        rewards_ = new Reward[](rewardRates.length);
        IExactlyPreviewer.ClaimableReward[] memory claimableRewards = marketAccount.claimableRewards;

        for (uint256 j = 0; j < rewardRates.length; j++) {
            IExactlyPreviewer.RewardRate memory rr = rewardRates[j];
            IERC20 token = IERC20(rr.asset);
            rewards_[j] = Reward({
                token: _asTokenData(token),
                rate: borrowing ? rr.borrow : rr.floatingDeposit,
                claimable: claimableRewards.find(rr.asset),
                usdPrice: rr.usdPrice
            });
        }
    }

}

function find(IExactlyPreviewer.ClaimableReward[] memory array, address value) pure returns (uint256) {
    for (uint256 i = 0; i < array.length; i++) {
        if (array[i].asset == value) return array[i].amount;
    }
    return 0;
}

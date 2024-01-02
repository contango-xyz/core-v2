//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

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
        (,,,, address priceFeed) = auditor.markets(reverseLookup.market(asset));
        return auditor.assetPrice(priceFeed);
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
        (uint256 collateralAdjustFactor,,,,) = auditor.markets(reverseLookup.market(collateralAsset));
        (uint256 debtAdjustFactor,,,,) = auditor.markets(reverseLookup.market(debtAsset));

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
        borrowing = market.interestRateModel().floatingRate(
            market.floatingAssets() > 0 ? Math.min(market.floatingDebt().mulDiv(WAD, market.floatingAssets(), Math.Rounding.Up), WAD) : 0
        );
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
                token: TokenData({
                    token: token,
                    name: rr.assetName,
                    symbol: rr.assetSymbol,
                    decimals: token.decimals(),
                    unit: 10 ** token.decimals()
                }),
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

//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./EulerMoneyMarket.sol";

import "../BaseMoneyMarketView.sol";
import { MM_EULER } from "script/constants.sol";

import "./dependencies/IEulerVaultLens.sol";

contract EulerMoneyMarketView is BaseMoneyMarketView {

    using Math for *;

    IERC20 public constant USD = IERC20(0x0000000000000000000000000000000000000348);

    EulerReverseLookup public immutable reverseLookup;
    EulerRewardsOperator public immutable rewardOperator;
    IEulerVaultLens public immutable lens;

    constructor(
        IContango _contango,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle,
        EulerReverseLookup _reverseLookup,
        EulerRewardsOperator _rewardOperator,
        IEulerVaultLens _lens
    ) BaseMoneyMarketView(MM_EULER, "Euler", _contango, _nativeToken, _nativeUsdOracle) {
        reverseLookup = _reverseLookup;
        rewardOperator = _rewardOperator;
        lens = _lens;
    }

    // ====== IMoneyMarketView =======

    function _prices(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Prices memory prices_)
    {
        IEulerVault quoteVault = reverseLookup.quote(positionId);
        IERC20 unitOfAccount = quoteVault.unitOfAccount();
        IEulerPriceOracle oracle = quoteVault.oracle();

        prices_.debt = oracle.getQuote(10 ** debtAsset.decimals(), debtAsset, unitOfAccount);
        prices_.collateral = oracle.getQuote(10 ** collateralAsset.decimals(), collateralAsset, unitOfAccount);
        prices_.unit = unitOfAccount == USD ? 1e18 : 10 ** unitOfAccount.decimals();
    }

    function _thresholds(PositionId positionId, IERC20, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        IEulerVault baseVault = reverseLookup.base(positionId);
        IEulerVault quoteVault = reverseLookup.quote(positionId);
        (uint256 borrowLTV, uint256 liquidationLTV,,,) = quoteVault.LTVFull(baseVault);

        ltv = borrowLTV * 1e14;
        liquidationThreshold = liquidationLTV * 1e14;
    }

    function _liquidity(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        IEulerVault baseVault = reverseLookup.base(positionId);
        lending = Math.min(baseVault.maxDeposit(_account(positionId)), collateralAsset.totalSupply());

        IEulerVault quoteVault = reverseLookup.quote(positionId);
        (, AmountCap borrowCapAmt) = quoteVault.caps();
        uint256 borrowCap = borrowCapAmt.resolve();
        borrowing = borrowCap == NO_CAP ? quoteVault.cash() : Math.min(quoteVault.cash(), borrowCap);
    }

    function _rates(PositionId positionId, IERC20, IERC20) internal view virtual override returns (uint256 borrowing, uint256 lending) { }

    function _irmRaw(PositionId positionId, IERC20, IERC20) internal view virtual override returns (bytes memory data) {
        data = abi.encode(rawData(positionId));
    }

    struct RewardsData {
        IEulerVaultLens.VaultRewardInfo rewardData;
        uint256 currentEpoch;
        uint256 claimable;
    }

    struct RawData {
        IEulerVaultLens.VaultInfoFull baseData;
        IEulerVaultLens.VaultInfoFull quoteData;
        RewardsData[] rewardsData;
    }

    // This function is here to make our life easier on the wagmi/viem side
    function rawData(PositionId positionId) public view returns (RawData memory data) {
        IEulerVault baseVault = reverseLookup.base(positionId);
        data.baseData = lens.getVaultInfoFull(baseVault);
        data.quoteData = lens.getVaultInfoFull(reverseLookup.quote(positionId));

        IRewardStreams rewardStreams = rewardOperator.rewardStreams();
        uint256 currentEpoch = rewardStreams.currentEpoch();
        address account = _account(positionId);
        address[] memory enabledRewards =
            positionId.getNumber() == 0 ? rewardOperator.liveRewards(baseVault) : rewardStreams.enabledRewards(account, baseVault);
        data.rewardsData = new RewardsData[](enabledRewards.length);
        for (uint256 i; i < enabledRewards.length; i++) {
            IERC20 reward = IERC20(enabledRewards[i]);
            data.rewardsData[i].rewardData = lens.getRewardVaultInfo(baseVault, reward, currentEpoch);
            data.rewardsData[i].claimable = rewardStreams.earnedReward(account, baseVault, reward, false);
            data.rewardsData[i].currentEpoch = currentEpoch;
        }
    }

    // So these functions can't be implemented
    // The reason why they are not made to revert is because Solidity would thrown an "Unreachable code" error
    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) { }
    function _oracleUnit() internal view virtual override returns (uint256) { }
    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) { }
    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) { }

}

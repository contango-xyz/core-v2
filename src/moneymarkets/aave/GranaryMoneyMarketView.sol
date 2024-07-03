//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../dependencies/Solidly.sol";
import "./dependencies/IPoolV2.sol";

import "./AaveV2MoneyMarketView.sol";
import { MM_GRANARY } from "script/constants.sol";

contract GranaryMoneyMarketView is AaveV2MoneyMarketView {

    // It looks unlikely we'll go anywhere else than Optimism, if that ever happens, we'll generalise this
    IGranaryRewarder public constant REWARDS_CONTROLLER = IGranaryRewarder(0x6A0406B8103Ec68EE9A713A073C7bD587c5e04aD);
    ISolidlyPool public constant REWARDS_TOKEN_ORACLE = ISolidlyPool(0xdc2B136A9C1FD2a0b9497bB8b11823c2FBf47Ac4);
    IERC20 public constant GRAIN = IERC20(0xfD389Dc9533717239856190F42475d3f263a270d);
    IERC20 public constant WETH = IERC20(0x4200000000000000000000000000000000000006);

    constructor(
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveOracle _oracle,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) AaveV2MoneyMarketView(MM_GRANARY, "Granary", _contango, _pool, _dataProvider, _oracle, 1e8, _nativeToken, _nativeUsdOracle) { }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        IERC20[] memory rewardTokens = REWARDS_CONTROLLER.getRewardsByAsset(_vToken(debtAsset));

        borrowing = new Reward[](1);
        uint256 j;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != GRAIN) continue;
            borrowing[j++] = _asRewards(positionId, debtAsset, true);
        }
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(borrowing, j)
        }

        rewardTokens = REWARDS_CONTROLLER.getRewardsByAsset(_aToken(collateralAsset));

        lending = new Reward[](1);
        j = 0;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != GRAIN) continue;
            lending[j++] = _asRewards(positionId, collateralAsset, false);
        }
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(lending, j)
        }

        _updateClaimable(positionId, borrowing, lending);
    }

    function _updateClaimable(PositionId positionId, Reward[] memory borrowing, Reward[] memory lending) internal view {
        uint256 stored = REWARDS_CONTROLLER.getUserUnclaimedRewardsFromStorage(_account(positionId), GRAIN);
        if (borrowing.length > 0 && lending.length > 0) {
            // When rewards are already accrued, we can't distinguish between borrowing and lending rewards.
            uint256 accruedByBorrowing = stored / 2;
            uint256 accruedByLending = stored - accruedByBorrowing;
            borrowing[0].claimable -= accruedByBorrowing;
            lending[0].claimable -= accruedByLending;
        }
    }

    function _asRewards(PositionId positionId, IERC20 asset, bool borrowing) internal view virtual returns (Reward memory rewards_) {
        IPoolV2.ReserveData memory reserve = poolV2.getReserveData(address(asset));
        IERC20 aToken = IERC20(borrowing ? reserve.variableDebtTokenAddress : reserve.aTokenAddress);
        IGranaryRewarder.RewardsData memory data = REWARDS_CONTROLLER.getRewardsData(aToken, GRAIN);

        rewards_.claimable =
            positionId.getNumber() > 0 ? REWARDS_CONTROLLER.getUserRewardsBalance(toArray(aToken), _account(positionId), GRAIN) : 0;
        rewards_.token = _asTokenData(GRAIN);
        rewards_.usdPrice = _rewardsTokenUSDPrice();

        if (block.timestamp > data.distributionEnd) return rewards_;

        rewards_.rate = _getIncentiveRate({
            tokenSupply: _getTokenSupply(asset, borrowing),
            emissionsPerSecond: data.emissionsPerSecond,
            priceShares: rewards_.usdPrice,
            tokenPrice: oracle.getAssetPrice(asset),
            decimals: asset.decimals(),
            precisionAdjustment: 1e10
        });
    }

    function _rewardsTokenUSDPrice() internal view virtual returns (uint256) {
        uint256 grainEth = REWARDS_TOKEN_ORACLE.getAmountOut(WAD, GRAIN);
        uint256 ethUsd = oracle.getAssetPrice(IERC20(0x4200000000000000000000000000000000000006));
        return grainEth * ethUsd / oracleUnit;
    }

    function _aToken(IERC20 asset) internal view virtual returns (IERC20 aToken) {
        aToken = IERC20(poolV2.getReserveData(address(asset)).aTokenAddress);
    }

    function _vToken(IERC20 asset) internal view virtual returns (IERC20 vToken) {
        vToken = IERC20(poolV2.getReserveData(address(asset)).variableDebtTokenAddress);
    }

}

interface IGranaryRewarder {

    struct RewardsConfigInput {
        uint88 emissionPerSecond;
        uint256 totalSupply;
        uint32 distributionEnd;
        address asset;
        address reward;
    }

    struct RewardsData {
        uint256 index;
        uint256 emissionsPerSecond;
        uint256 indexLastUpdated;
        uint256 distributionEnd;
    }

    function claimAllRewards(IERC20[] memory assets, address to)
        external
        returns (IERC20[] memory rewardTokens, uint256[] memory claimedAmounts);
    function claimAllRewardsOnBehalf(IERC20[] memory assets, address user, address to)
        external
        returns (IERC20[] memory rewardTokens, uint256[] memory claimedAmounts);
    function claimAllRewardsToSelf(IERC20[] memory assets)
        external
        returns (IERC20[] memory rewardTokens, uint256[] memory claimedAmounts);
    function claimRewards(IERC20[] memory assets, uint256 amount, address to, IERC20 reward) external returns (uint256);
    function claimRewardsOnBehalf(IERC20[] memory assets, uint256 amount, address user, address to, address reward)
        external
        returns (uint256);
    function claimRewardsToSelf(IERC20[] memory assets, uint256 amount, IERC20 reward) external returns (uint256);
    function getAllUserRewardsBalance(IERC20[] memory assets, address user)
        external
        view
        returns (IERC20[] memory rewardTokens, uint256[] memory unclaimedAmounts);
    function getAssetDecimals(IERC20 asset) external view returns (uint8);
    function getClaimer(address user) external view returns (address);
    function getDistributionEnd(IERC20 asset, IERC20 reward) external view returns (uint256);
    function getRewardTokens() external view returns (address[] memory);
    function getRewardsByAsset(IERC20 asset) external view returns (IERC20[] memory);
    function getRewardsData(IERC20 asset, IERC20 reward) external view returns (RewardsData memory);
    function getRewardsVault(IERC20 reward) external view returns (address);
    function getUserAssetData(address user, IERC20 asset, IERC20 reward) external view returns (uint256);
    function getUserRewardsBalance(IERC20[] memory assets, address user, IERC20 reward) external view returns (uint256);
    function getUserUnclaimedRewardsFromStorage(address user, IERC20 reward) external view returns (uint256);
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;
    function owner() external view returns (address);

}

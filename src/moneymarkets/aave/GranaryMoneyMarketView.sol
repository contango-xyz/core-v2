//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "../../dependencies/Solidly.sol";
import "./dependencies/IPoolV2.sol";
import "./dependencies/IPoolDataProviderV2.sol";

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

        borrowing = new Reward[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != GRAIN) continue;
            borrowing[i] = _asRewards(positionId, debtAsset, true);
        }

        rewardTokens = REWARDS_CONTROLLER.getRewardsByAsset(_aToken(collateralAsset));

        lending = new Reward[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] != GRAIN) continue;
            lending[i] = _asRewards(positionId, collateralAsset, false);
        }
    }

    function _asRewards(PositionId positionId, IERC20 asset, bool borrowing) internal view virtual returns (Reward memory rewards_) {
        IPoolV2.ReserveData memory reserve = poolV2.getReserveData(address(asset));
        IERC20 aToken = IERC20(borrowing ? reserve.variableDebtTokenAddress : reserve.aTokenAddress);
        (, uint256 emissionsPerSecond,,) = REWARDS_CONTROLLER.getRewardsData(aToken, GRAIN);

        rewards_.usdPrice = _rewardsTokenUSDPrice();

        rewards_.token = TokenData({
            token: GRAIN,
            name: GRAIN.name(),
            symbol: GRAIN.symbol(),
            decimals: GRAIN.decimals(),
            unit: 10 ** GRAIN.decimals()
        });

        rewards_.rate = _getIncentiveRate({
            tokenSupply: _getTokenSupply(asset, borrowing),
            emissionPerSecond: emissionsPerSecond,
            priceShares: rewards_.usdPrice,
            tokenPrice: oracle.getAssetPrice(asset),
            decimals: IERC20(asset).decimals()
        });

        rewards_.claimable =
            positionId.getNumber() > 0 ? REWARDS_CONTROLLER.getUserRewardsBalance(toArray(aToken), _account(positionId), GRAIN) : 0;
    }

    function _getTokenSupply(IERC20 asset, bool borrowing) internal view returns (uint256 tokenSupply) {
        (uint256 availableLiquidity,, uint256 totalVariableDebt,,,,,,,) =
            IPoolDataProviderV2(address(dataProvider)).getReserveData(address(asset));

        tokenSupply = borrowing ? totalVariableDebt : availableLiquidity + totalVariableDebt;
    }

    function _getIncentiveRate(uint256 tokenSupply, uint256 emissionPerSecond, uint256 priceShares, uint256 tokenPrice, uint8 decimals)
        public
        pure
        returns (uint256)
    {
        uint256 emissionPerYear = emissionPerSecond * 365 days;
        uint256 totalSupplyInDaiWei = tokenSupply * tokenPrice / (10 ** decimals);
        uint256 apyPerYear = totalSupplyInDaiWei != 0 ? priceShares * emissionPerYear / totalSupplyInDaiWei : 0;
        // Adjust decimals
        return apyPerYear / 1e10;
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
    function getRewardsData(IERC20 asset, IERC20 reward) external view returns (uint256, uint256, uint256, uint256);
    function getRewardsVault(IERC20 reward) external view returns (address);
    function getUserAssetData(address user, IERC20 asset, IERC20 reward) external view returns (uint256);
    function getUserRewardsBalance(IERC20[] memory assets, address user, IERC20 reward) external view returns (uint256);
    function getUserUnclaimedRewardsFromStorage(address user, IERC20 reward) external view returns (uint256);
    function handleAction(address user, uint256 totalSupply, uint256 userBalance) external;
    function owner() external view returns (address);

}

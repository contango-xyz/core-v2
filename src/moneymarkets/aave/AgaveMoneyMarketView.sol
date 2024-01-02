//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "./AaveV2MoneyMarketView.sol";
import "./dependencies/IAgaveBaseIncentivesController.sol";
import "../../dependencies/Balancer.sol";
import { MM_AGAVE } from "script/constants.sol";

contract AgaveMoneyMarketView is AaveV2MoneyMarketView {

    IAgaveBaseIncentivesController public immutable INCENTIVES_CONTROLLER =
        IAgaveBaseIncentivesController(0xfa255f5104f129B78f477e9a6D050a02f31A5D86);
    IBalancerVault public constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IERC20 public constant GNO = IERC20(0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb);
    bytes32 public constant REWARDS_POOL_ID = 0x388cae2f7d3704c937313d990298ba67d70a3709000200000000000000000026;

    constructor(
        IContango _contango,
        IPool _pool,
        IPoolDataProvider _dataProvider,
        IAaveOracle _oracle,
        IWETH9 _nativeToken,
        IAggregatorV2V3 _nativeUsdOracle
    ) AaveV2MoneyMarketView(MM_AGAVE, "Agave", _contango, _pool, _dataProvider, _oracle, WAD, _nativeToken, _nativeUsdOracle) { }

    // ====== IMoneyMarketView =======

    function _borrowingLiquidity(IERC20 asset) internal view override returns (uint256 borrowingLiquidity_) {
        uint256 borrowCap = poolV2.getReserveLimits(address(asset)).borrowLimit;

        IPoolV2.ReserveData memory reserve = poolV2.getReserveData(address(asset));

        uint256 totalDebt = IERC20(reserve.stableDebtTokenAddress).totalSupply() + IERC20(reserve.variableDebtTokenAddress).totalSupply();

        uint256 maxBorrowable = borrowCap > totalDebt ? borrowCap - totalDebt : 0;

        uint256 available = asset.balanceOf(reserve.aTokenAddress);

        borrowingLiquidity_ = borrowCap == 0 ? available : Math.min(maxBorrowable, available);
    }

    function _lendingLiquidity(IERC20 asset) internal view override returns (uint256 lendingLiquidity_) {
        (,,,,, bool usageAsCollateralEnabled,,,,) = dataProvider.getReserveConfigurationData(address(asset));
        if (!usageAsCollateralEnabled) return 0;

        uint256 supplyCap = poolV2.getReserveLimits(address(asset)).depositLimit;
        uint256 currentSupply = IERC20(poolV2.getReserveData(address(asset)).aTokenAddress).totalSupply();
        lendingLiquidity_ = supplyCap > currentSupply ? supplyCap - currentSupply : 0;
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        borrowing = new Reward[](1);
        borrowing[0] = _asRewards(positionId, debtAsset, true);

        lending = new Reward[](1);
        lending[0] = _asRewards(positionId, collateralAsset, false);
    }

    function _asRewards(PositionId positionId, IERC20 asset, bool borrowing) internal view returns (Reward memory rewards_) {
        IPoolV2.ReserveData memory reserve = poolV2.getReserveData(address(asset));
        IERC20 aToken = IERC20(borrowing ? reserve.variableDebtTokenAddress : reserve.aTokenAddress);
        (, uint256 emissionsPerSecond,,,) = INCENTIVES_CONTROLLER.getAssetData(aToken);

        IERC20 rewardsToken = INCENTIVES_CONTROLLER.REWARD_TOKEN();
        uint256 gnoPrice = oracle.getAssetPrice(GNO);
        (uint256 gnoPoolBalance,,,) = BALANCER.getPoolTokenInfo(REWARDS_POOL_ID, address(GNO));
        (IBalancerWeightedPool pool,) = BALANCER.getPool(REWARDS_POOL_ID);

        // It's a balancer 50/50 pool, so the total USD value of the pool is roughtly 2x the GNO balance
        rewards_.usdPrice = gnoPrice * gnoPoolBalance * 2 / pool.getActualSupply();

        rewards_.token = TokenData({
            token: rewardsToken,
            name: rewardsToken.name(),
            symbol: rewardsToken.symbol(),
            decimals: rewardsToken.decimals(),
            unit: 10 ** rewardsToken.decimals()
        });

        rewards_.rate = _getIncentiveRate({
            tokenSupply: _getTokenSupply(asset, borrowing),
            emissionPerSecond: emissionsPerSecond,
            priceShares: rewards_.usdPrice,
            tokenPrice: oracle.getAssetPrice(asset),
            decimals: IERC20(asset).decimals()
        });

        rewards_.claimable = positionId.getNumber() > 0 ? INCENTIVES_CONTROLLER.getRewardsBalance(toArray(aToken), _account(positionId)) : 0;
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
        return apyPerYear / 1e3;
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../dependencies/Chainlink.sol";
import "../../libraries/Arrays.sol";

import "./Silo.sol";
import "../BaseMoneyMarketView.sol";
import { MM_SILO } from "script/constants.sol";

contract SiloMoneyMarketView is BaseMoneyMarketView {

    error OracleBaseCurrencyNotUSD();

    using Math for *;

    ISiloLens public constant LENS = ISiloLens(0x07b94eB6AaD663c4eaf083fBb52928ff9A15BE47);
    ISiloIncentivesController public constant INCENTIVES_CONTROLLER = ISiloIncentivesController(0xd592F705bDC8C1B439Bd4D665Ed99C4FaAd5A680);
    ISilo public constant WSTETH_SILO = ISilo(0xA8897b4552c075e884BDB8e7b704eB10DB29BF0D);
    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 public constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    ISiloRepository public immutable repository = LENS.siloRepository();
    ISiloPriceProvidersRepository public immutable priceProvidersRepository;

    constructor(IContango _contango, IWETH9 _nativeToken, IAggregatorV2V3 _nativeUsdOracle)
        BaseMoneyMarketView(MM_SILO, "Silo", _contango, _nativeToken, _nativeUsdOracle)
    {
        priceProvidersRepository = repository.priceProvidersRepository();
    }

    // ====== IMoneyMarketView =======

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        ISilo silo = _silo(collateralAsset);
        silo.accrueInterest(collateralAsset);
        silo.accrueInterest(debtAsset);
        balances_.collateral = LENS.collateralBalanceOfUnderlying(silo, collateralAsset, account);
        balances_.debt = LENS.getBorrowAmount(silo, debtAsset, account, block.timestamp);
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return 10 ** priceProvidersRepository.QUOTE_TOKEN_DECIMALS();
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        return priceProvidersRepository.getPrice(asset);
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        ISiloRepository.AssetConfig memory assetConfig = repository.assetConfigs(_silo(collateralAsset), collateralAsset);
        ltv = assetConfig.maxLoanToValue;
        liquidationThreshold = assetConfig.liquidationThreshold;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        ISilo silo = _silo(collateralAsset);
        borrowing = LENS.liquidity(silo, debtAsset);

        uint256 maxDepositValue = repository.getMaxSiloDepositsValue(silo, collateralAsset);
        if (maxDepositValue == type(uint256).max) {
            lending = collateralAsset.totalSupply();
        } else {
            ISilo.AssetStorage memory assetState = silo.assetStorage(collateralAsset);
            uint256 price = priceProvidersRepository.getPrice(collateralAsset);
            uint256 deposits = assetState.totalDeposits + assetState.collateralOnlyDeposits;
            uint256 unit = 10 ** collateralAsset.decimals();
            uint256 depositsValue = deposits * price / unit;
            if (depositsValue > maxDepositValue) lending = 0;
            else lending = (maxDepositValue - depositsValue) * unit / price;
        }
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        ISilo silo = _silo(collateralAsset);
        borrowing = LENS.borrowAPY(silo, debtAsset);
        lending = LENS.depositAPY(silo, collateralAsset);
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        ISilo silo = _silo(collateralAsset);
        borrowing = _asRewards({ positionId: positionId, silo: silo, asset: debtAsset, lending: false });
        lending = _asRewards({ positionId: positionId, silo: silo, asset: collateralAsset, lending: true });
    }

    function priceInUSD(IERC20 asset) public view override returns (uint256 price_) {
        if (asset == nativeToken) return uint256(nativeUsdOracle.latestAnswer()) * 1e10;
        return _oraclePrice(asset) * uint256(nativeUsdOracle.latestAnswer()) / 1e8;
    }

    // ===== Internal Helper Functions =====

    function _asRewards(PositionId positionId, ISilo silo, IERC20 asset, bool lending) internal view returns (Reward[] memory rewards_) {
        IERC20 siloAsset = lending ? silo.assetStorage(asset).collateralToken : silo.assetStorage(asset).debtToken;
        uint256 emissionPerSecond = INCENTIVES_CONTROLLER.getAssetData(siloAsset).emissionPerSecond;
        if (emissionPerSecond == 0) return new Reward[](0);
        rewards_ = new Reward[](1);
        Reward memory reward;

        IERC20 rewardsToken = INCENTIVES_CONTROLLER.REWARD_TOKEN();

        reward.usdPrice = priceInUSD(rewardsToken);
        reward.token = TokenData({
            token: rewardsToken,
            name: rewardsToken.name(),
            symbol: rewardsToken.symbol(),
            decimals: rewardsToken.decimals(),
            unit: 10 ** rewardsToken.decimals()
        });

        uint256 valueOfEmissions = (emissionPerSecond * 365 days) * reward.usdPrice / 1e18;
        uint256 assetPrice = priceInUSD(asset);

        if (lending) {
            uint256 assetSupplied = silo.assetStorage(asset).totalDeposits;
            uint256 valueOfAssetsSupplied = assetPrice * assetSupplied / 10 ** asset.decimals();

            reward.rate = valueOfEmissions * 1e18 / valueOfAssetsSupplied;

            if (reward.rate > 0 && positionId.getNumber() > 0) {
                address account = _account(positionId);
                reward.claimable = INCENTIVES_CONTROLLER.getRewardsBalance(toArray(siloAsset), account);
            }
        }

        rewards_[0] = reward;
    }

    function _silo(IERC20 asset) internal view returns (ISilo silo) {
        silo = (asset == WETH || asset == USDC) ? WSTETH_SILO : repository.getSilo(asset);
    }

}

//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./dependencies/IFluidLiquidityResolver.sol";
import "./dependencies/IFluidVaultResolver.sol";

import "../BaseMoneyMarketView.sol";
import { MM_FLUID } from "script/constants.sol";

contract FluidMoneyMarketView is BaseMoneyMarketView {

    using Math for *;

    IFluidVaultResolver public immutable vaultResolver;
    IFluidLiquidityResolver public immutable liquidityResolver;

    constructor(IContango _contango, IWETH9 _nativeToken, IAggregatorV2V3 _nativeUsdOracle, IFluidVaultResolver _vaultResolver)
        BaseMoneyMarketView(MM_FLUID, "Fluid", _contango, _nativeToken, _nativeUsdOracle)
    {
        vaultResolver = _vaultResolver;
        liquidityResolver = _vaultResolver.LIQUIDITY_RESOLVER();
    }

    // ====== IMoneyMarketView =======

    function _prices(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Prices memory prices_)
    {
        IFluidVaultResolver.VaultEntireData memory vaultData = vaultResolver.getVaultEntireData(vault(positionId));
        prices_.collateral = vaultData.configs.oraclePriceOperate * (10 ** collateralAsset.decimals()) / 1e27;
        prices_.debt = prices_.unit = 10 ** debtAsset.decimals();
    }

    function _thresholds(PositionId positionId, IERC20, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        IFluidVaultResolver.VaultEntireData memory vaultData = vaultResolver.getVaultEntireData(vault(positionId));

        ltv = uint256(vaultData.configs.collateralFactor) * 1e14;
        liquidationThreshold = uint256(vaultData.configs.liquidationThreshold) * 1e14;
    }

    function _liquidity(PositionId positionId, IERC20 collateralAsset, IERC20)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        IFluidVaultResolver.VaultEntireData memory vaultData = vaultResolver.getVaultEntireData(vault(positionId));

        borrowing = vaultData.limitsAndAvailability.borrowable;
        lending = collateralAsset.totalSupply();
    }

    function _rates(PositionId positionId, IERC20, IERC20) internal view virtual override returns (uint256 borrowing, uint256 lending) { }

    function _irmRaw(PositionId positionId, IERC20, IERC20) internal view virtual override returns (bytes memory data) {
        data = abi.encode(rawData(positionId));
    }

    struct RawData {
        IFluidVaultResolver.VaultEntireData vaultData;
        IFluidLiquidityResolver.OverallTokenData baseTokenData;
        IFluidLiquidityResolver.OverallTokenData quoteTokenData;
    }

    // This function is here to make our life easier on the wagmi/viem side
    function rawData(PositionId positionId) public view returns (RawData memory data) {
        IFluidVault vault_ = vault(positionId);
        data.vaultData = vaultResolver.getVaultEntireData(vault_);
        data.baseTokenData = liquidityResolver.getOverallTokenData(data.vaultData.constantVariables.supplyToken);
        data.quoteTokenData = liquidityResolver.getOverallTokenData(data.vaultData.constantVariables.borrowToken);
    }

    // So these functions can't be implemented
    // The reason why they are not made to revert is because Solidity would thrown an "Unreachable code" error
    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) { }
    function _oracleUnit() internal view virtual override returns (uint256) { }
    function priceInUSD(IERC20 asset) public view virtual override returns (uint256 price_) { }
    function priceInNativeToken(IERC20 asset) public view virtual override returns (uint256 price_) { }

    function vault(PositionId positionId) public view returns (IFluidVault) {
        return vaultResolver.getVaultAddress(uint40(Payload.unwrap(positionId.getPayload())));
    }

}

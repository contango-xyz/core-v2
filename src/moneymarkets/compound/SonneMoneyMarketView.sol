//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { ISolidlyPool } from "../../dependencies/Solidly.sol";
import "./CompoundMoneyMarketView.sol";
import "./dependencies/IChainlinkPriceOracle.sol";
import { MM_SONNE } from "script/constants.sol";

contract SonneMoneyMarketView is CompoundMoneyMarketView {

    constructor(IContango _contango, CompoundReverseLookup _reverseLookup, address _rewardsTokenOracle, IAggregatorV2V3 _nativeUsdOracle)
        CompoundMoneyMarketView(MM_SONNE, "Sonne", _contango, _reverseLookup, _rewardsTokenOracle, _nativeUsdOracle)
    { }

    function _oraclePrice(IERC20 asset) internal view override returns (uint256 price) {
        return IChainlinkPriceOracle(comptroller.oracle()).getPrice(_cToken(asset));
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return WAD;
    }

    function _blocksPerDay() internal pure virtual override returns (uint256) {
        // Sonne uses timestamp instead of blocks, so Blocks Per Day is actually Seconds Per Day
        return 1 days;
    }

    function _rewardsTokenUSDPrice() internal view virtual override returns (uint256) {
        return ISolidlyPool(rewardsTokenOracle).getAmountOut(WAD, comptroller.getCompAddress()) * 1e12;
    }

    function _getBlockNumber() internal view virtual override returns (uint256) {
        // Sonne uses timestamp instead of blocks
        return block.timestamp;
    }

    function _borrowingLiquidity(IERC20 asset) internal view virtual override returns (uint256) {
        ICToken cToken = _cToken(asset);
        uint256 cap = comptroller.borrowCaps(cToken);
        uint256 available = asset.balanceOf(address(cToken)) * 0.95e18 / WAD;
        if (cap == 0) return available;

        uint256 borrowed = cToken.totalBorrows();
        if (borrowed > cap) return 0;

        return Math.min(cap - borrowed, available);
    }

}

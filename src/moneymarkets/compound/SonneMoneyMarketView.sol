//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

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

    function _rateFrequency() internal pure virtual override returns (uint256) {
        return 1;
    }

    function _rewardsTokenUSDPrice() internal view virtual override returns (uint256) {
        return ISolidlyPool(rewardsTokenOracle).getAmountOut(WAD, comptroller.getCompAddress()) * 1e12;
    }

    function _getBlockNumber() internal view virtual override returns (uint256) {
        // Sonne uses timestamp instead of blocks
        return block.timestamp;
    }

    function _cTokenBalance(IERC20 asset, ICToken cToken) internal view virtual override returns (uint256) {
        return asset.balanceOf(address(cToken));
    }

}

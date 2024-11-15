//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../libraries/DataTypes.sol";
import "../../dependencies/IWETH9.sol";
import "./dependencies/IComptroller.sol";

interface CompoundReverseLookupEvents {

    event CTokenSet(IERC20 indexed asset, ICToken indexed cToken);

}

contract CompoundReverseLookup is CompoundReverseLookupEvents {

    error CTokenNotFound(IERC20 asset);
    error CTokenNotListed(ICToken cToken);

    IComptroller public immutable comptroller;
    IWETH9 public immutable nativeToken;

    mapping(IERC20 token => ICToken cToken) public cTokens;
    mapping(ICToken cToken => IERC20 token) public assets;

    constructor(IComptroller _comptroller, IWETH9 _nativeToken) {
        comptroller = _comptroller;
        nativeToken = _nativeToken;
    }

    function setCToken(ICToken _cToken) external {
        require(comptroller.markets(_cToken).isListed, CTokenNotListed(_cToken));
        IERC20 asset = _cTokenUnderlying(_cToken);

        cTokens[asset] = _cToken;
        assets[_cToken] = asset;
        emit CTokenSet(asset, _cToken);
    }

    function cToken(IERC20 asset) external view returns (ICToken _cToken) {
        _cToken = cTokens[asset];
        if (_cToken == ICToken(address(0))) revert CTokenNotFound(asset);
    }

    function _cTokenUnderlying(ICToken _cToken) internal view returns (IERC20) {
        try _cToken.underlying() returns (IERC20 token) {
            return token;
        } catch {
            return nativeToken;
        }
    }

}

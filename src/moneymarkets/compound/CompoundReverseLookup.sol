//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "../../libraries/DataTypes.sol";
import "../../dependencies/IWETH9.sol";
import "./dependencies/IComptroller.sol";

interface CompoundReverseLookupEvents {

    event CTokenSet(IERC20 indexed asset, ICToken indexed cToken);

}

contract CompoundReverseLookup is CompoundReverseLookupEvents, AccessControl {

    error CTokenNotFound(IERC20 asset);

    IComptroller public immutable comptroller;
    IWETH9 public immutable nativeToken;

    mapping(IERC20 token => ICToken cToken) private _cTokens;

    constructor(Timelock timelock, IComptroller _comptroller, IWETH9 _nativeToken) {
        comptroller = _comptroller;
        nativeToken = _nativeToken;
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function update() external {
        _update(comptroller);
    }

    function _update(IComptroller _comptroller) private {
        if (address(_comptroller) != address(0)) {
            ICToken[] memory allMarkets = comptroller.getAllMarkets();
            for (uint256 i = 0; i < allMarkets.length; i++) {
                ICToken _cToken = allMarkets[i];
                try _cToken.underlying() returns (IERC20 token) {
                    _cTokens[token] = _cToken;
                    emit CTokenSet(token, _cToken);
                } catch {
                    // fails for native token, e.g. mainnet cETH
                    if (address(nativeToken) != address(0)) {
                        _cTokens[nativeToken] = _cToken;
                        emit CTokenSet(nativeToken, _cToken);
                    }
                }
            }
        }
    }

    function setCToken(IERC20 asset, ICToken _cToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _cTokens[asset] = _cToken;
        emit CTokenSet(asset, _cToken);
    }

    function cToken(IERC20 asset) external view returns (ICToken _cToken) {
        _cToken = _cTokens[asset];
        if (_cToken == ICToken(address(0))) revert CTokenNotFound(asset);
    }

}

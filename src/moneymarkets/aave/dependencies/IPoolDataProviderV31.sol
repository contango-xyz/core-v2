// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./IPoolDataProviderV3.sol";

interface IPoolDataProviderV31 is IPoolDataProviderV3 {

    function getIsVirtualAccActive(address asset) external view returns (bool);
    function getVirtualUnderlyingBalance(address asset) external view returns (uint256);

}

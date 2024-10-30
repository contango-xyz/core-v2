// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./IPoolV2.sol";

interface IPoolAddressesProviderV2 {

    event AddressSet(bytes32 id, address indexed newAddress, bool hasProxy);
    event ConfigurationAdminUpdated(address indexed newAddress);
    event EmergencyAdminUpdated(address indexed newAddress);
    event LendingPoolCollateralManagerUpdated(address indexed newAddress);
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event LendingPoolUpdated(address indexed newAddress);
    event LendingRateOracleUpdated(address indexed newAddress);
    event MarketIdSet(string newMarketId);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PriceOracleUpdated(address indexed newAddress);
    event ProxyCreated(bytes32 id, address indexed newAddress);

    function getAddress(bytes32 id) external view returns (address);
    function getEmergencyAdmin() external view returns (address);
    function getLendingPool() external view returns (IPoolV2);
    function getLendingPoolCollateralManager() external view returns (address);
    function getLendingPoolConfigurator() external view returns (address);
    function getLendingRateOracle() external view returns (address);
    function getMarketId() external view returns (string memory);
    function getPoolAdmin() external view returns (address);
    function getPriceOracle() external view returns (address);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function setAddress(bytes32 id, address newAddress) external;
    function setAddressAsProxy(bytes32 id, address implementationAddress) external;
    function setEmergencyAdmin(address emergencyAdmin) external;
    function setLendingPoolCollateralManager(address manager) external;
    function setLendingPoolConfiguratorImpl(address configurator) external;
    function setLendingPoolImpl(address pool) external;
    function setLendingRateOracle(address lendingRateOracle) external;
    function setMarketId(string memory marketId) external;
    function setPoolAdmin(address admin) external;
    function setPriceOracle(address priceOracle) external;
    function transferOwnership(address newOwner) external;

}

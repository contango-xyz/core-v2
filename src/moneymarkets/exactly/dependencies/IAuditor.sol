//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IMarket.sol";

interface IAuditor {

    error AuditorMismatch(); // "0x16b2972f",
    error InsufficientAccountLiquidity(); // "0x15d58176",
    error InsufficientShortfall(); // "0x095bf333",
    error InvalidPrice(); // "0x00bfc921",
    error InvalidPriceFeed(); // "0x52cc3f7d",
    error MarketAlreadyListed(); // "0x4d5eeb49",
    error MarketNotListed(); // "0x69609fc6",
    error NotMarket(); // "0xc4bbea69",
    error RemainingDebt(); // "0x9fb60220"

    event AdjustFactorSet(address indexed market, uint256 adjustFactor);
    event Initialized(uint8 version);
    event LiquidationIncentiveSet(LiquidationIncentive liquidationIncentive);
    event MarketEntered(address indexed market, address indexed account);
    event MarketExited(address indexed market, address indexed account);
    event MarketListed(address indexed market, uint8 decimals);
    event PriceFeedSet(address indexed market, address indexed priceFeed);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    struct LiquidationIncentive {
        uint128 liquidator;
        uint128 lenders;
    }

    function ASSETS_THRESHOLD() external view returns (uint256);
    function BASE_FEED() external view returns (address);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function TARGET_HEALTH() external view returns (uint256);
    function accountLiquidity(address account, IMarket marketToSimulate, uint256 withdrawAmount)
        external
        view
        returns (uint256 sumCollateral, uint256 sumDebtPlusEffects);
    function accountMarkets(address) external view returns (uint256);
    function allMarkets() external view returns (IMarket[] memory);
    function assetPrice(address priceFeed) external view returns (uint256);
    function calculateSeize(address repayMarket, address seizeMarket, address borrower, uint256 actualRepayAssets)
        external
        view
        returns (uint256 lendersAssets, uint256 seizeAssets);
    function checkBorrow(address market, address borrower) external;
    function checkLiquidation(address repayMarket, address seizeMarket, address borrower, uint256 maxLiquidatorAssets)
        external
        view
        returns (uint256 maxRepayAssets);
    function checkSeize(IMarket repayMarket, IMarket seizeMarket) external view;
    function checkShortfall(IMarket market, address account, uint256 amount) external view;
    function enableMarket(IMarket market, address priceFeed, uint128 adjustFactor) external;
    function enterMarket(IMarket market) external;
    function exitMarket(IMarket market) external;
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function handleBadDebt(address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initialize(LiquidationIncentive memory liquidationIncentive_) external;
    function liquidationIncentive() external view returns (uint128 liquidator, uint128 lenders);
    function marketList(uint256) external view returns (address);
    function markets(IMarket) external view returns (uint128 adjustFactor, uint8 decimals, uint8 index, bool isListed, address priceFeed);
    function priceDecimals() external view returns (uint256);
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function setAdjustFactor(address market, uint128 adjustFactor) external;
    function setLiquidationIncentive(LiquidationIncentive memory liquidationIncentive_) external;
    function setPriceFeed(address market, address priceFeed) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}

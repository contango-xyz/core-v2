// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IEulerPriceOracle } from "./IEulerPriceOracle.sol";

interface IEulerRouter {

    error ControllerDisabled();
    error EVC_InvalidAddress();
    error Governance_CallerNotGovernor();
    error NotAuthorized();
    error PriceOracle_InvalidConfiguration();
    error PriceOracle_NotSupported(IERC20 base, IERC20 quote);

    event ConfigSet(address indexed asset0, address indexed asset1, address indexed oracle);
    event FallbackOracleSet(address indexed fallbackOracle);
    event GovernorSet(address indexed oldGovernor, address indexed newGovernor);
    event ResolvedVaultSet(address indexed vault, address indexed asset);

    function EVC() external view returns (address);
    function fallbackOracle() external view returns (address);
    function getConfiguredOracle(IERC20 base, IERC20 quote) external view returns (IEulerPriceOracle);
    function getQuote(uint256 inAmount, IERC20 base, IERC20 quote) external view returns (uint256);
    function getQuotes(uint256 inAmount, IERC20 base, IERC20 quote) external view returns (uint256, uint256);
    function govSetConfig(IERC20 base, IERC20 quote, address oracle) external;
    function govSetFallbackOracle(address _fallbackOracle) external;
    function govSetResolvedVault(address vault, bool set) external;
    function governor() external view returns (address);
    function name() external view returns (string memory);
    function resolveOracle(uint256 inAmount, IERC20 base, IERC20 quote) external view returns (uint256, address, address, address);
    function resolvedVaults(address vault) external view returns (address asset);
    function transferGovernance(address newGovernor) external;

}

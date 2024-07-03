// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IIsolationVault.sol";

interface IIsolationToken is IERC20 {

    function BORROW_POSITION_PROXY() external view returns (address);
    function DOLOMITE_MARGIN() external view returns (address);
    function UNDERLYING_TOKEN() external view returns (IERC20);
    function allowableCollateralMarketIds() external pure returns (uint256[] memory);
    function allowableDebtMarketIds() external pure returns (uint256[] memory);
    function calculateVaultByAccount(address _account) external view returns (address _vault);
    function createVault(address _account) external returns (IIsolationVault);
    function createVaultAndDepositIntoDolomiteMargin(uint256 _toAccountNumber, uint256 _amountWei) external returns (IIsolationVault);
    function depositIntoDolomiteMargin(uint256 _toAccountNumber, uint256 _amountWei) external;
    function depositOtherTokenIntoDolomiteMarginForVaultOwner(uint256 _toAccountNumber, uint256 _otherMarketId, uint256 _amountWei)
        external;
    function getAccountByVault(address _vault) external view returns (address _account);
    function getVaultByAccount(address _account) external view returns (address _vault);
    function isInitialized() external view returns (bool);
    function isIsolationAsset() external pure returns (bool);
    function isTokenConverterTrusted(address _tokenConverter) external view returns (bool);
    function marketId() external view returns (uint256);
    function userVaultImplementation() external view returns (address);
    function withdrawFromDolomiteMargin(uint256 _fromAccountNumber, uint256 _amountWei) external;

}

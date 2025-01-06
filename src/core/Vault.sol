//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IVault.sol";
import "../libraries/DataTypes.sol";
import "../libraries/ERC20Lib.sol";
import { CONTANGO_ROLE, OPERATOR_ROLE } from "../libraries/Roles.sol";
import { SenderIsNotNativeToken } from "../libraries/Errors.sol";

contract Vault is IVault, ReentrancyGuardUpgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {

    using ERC20Lib for IERC20;
    using ERC20Lib for IWETH9;

    struct TokenData {
        bool isSupported;
        uint256 totalBalance;
        mapping(address owner => uint256 balance) accountBalances;
    }

    IWETH9 public immutable nativeToken;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * mixins without shifting down storage in this contract.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     *
     * After adding some OZ mixins, we consumed 301 slots from the original 50k gap.
     */
    uint256[50_000 - 301] private __gap;

    uint256[4] private __dead; // Storage was replaced on this contract so we kill the slots to avoid dirty reads
    mapping(IERC20 token => TokenData tokenData) private tokens;

    constructor(IWETH9 _nativeToken) {
        nativeToken = _nativeToken;
    }

    function initialize(Timelock timelock) public initializer {
        __ReentrancyGuard_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _setTokenSupport(nativeToken, true);
    }

    function setTokenSupport(IERC20 token, bool isSupported) external onlyRole(OPERATOR_ROLE) {
        _setTokenSupport(token, isSupported);
    }

    function _setTokenSupport(IERC20 token, bool isSupported) internal {
        tokens[token].isSupported = isSupported;
        emit TokenSupportSet(token, isSupported);
    }

    function isTokenSupported(IERC20 token) external view override returns (bool) {
        return tokens[token].isSupported;
    }

    function balanceOf(IERC20 token, address owner) public view returns (uint256) {
        return tokens[token].accountBalances[owner];
    }

    function totalBalanceOf(IERC20 token) public view returns (uint256) {
        return tokens[token].totalBalance;
    }

    function _deposit(IERC20 token, address payer, address account, uint256 amount) private returns (uint256) {
        _validAmount(amount);
        TokenData storage tokenData = tokens[token];
        if (!tokenData.isSupported) revert UnsupportedToken(token);

        uint256 available = token.balanceOf(address(this)) - tokenData.totalBalance;
        tokenData.totalBalance += amount;
        tokenData.accountBalances[account] += amount;

        if (available < amount) token.transferOut({ payer: payer, to: address(this), amount: amount - available });

        emit Deposited(token, account, amount);

        return amount;
    }

    function deposit(IERC20 token, address account, uint256 amount) public override authorised(account) returns (uint256) {
        return _deposit({ token: token, payer: account, account: account, amount: amount });
    }

    function depositTo(IERC20 token, address account, uint256 amount) public override returns (uint256) {
        return _deposit({ token: token, payer: msg.sender, account: account, amount: amount });
    }

    function depositNative(address account) public payable authorised(account) returns (uint256) {
        uint256 amount = msg.value;
        _validAmount(amount);

        nativeToken.deposit{ value: amount }();
        return deposit(nativeToken, account, amount);
    }

    function withdraw(IERC20 token, address account, uint256 amount, address to) public authorised(account) returns (uint256) {
        return _withdraw(token, account, amount, to, IWETH9(address(0)));
    }

    function withdrawNative(address account, uint256 amount, address to) external authorised(account) returns (uint256) {
        return _withdraw(nativeToken, account, amount, to, nativeToken);
    }

    function _withdraw(IERC20 token, address account, uint256 amount, address to, IWETH9 _nativeToken) internal returns (uint256) {
        _validAmount(amount);
        TokenData storage tokenData = tokens[token];
        uint256 balance = tokenData.accountBalances[account];
        if (balance < amount) revert NotEnoughBalance(token, balance, amount);

        tokenData.accountBalances[account] -= amount;
        tokenData.totalBalance -= amount;

        if (address(token) == address(_nativeToken)) _nativeToken.transferOutNative({ to: payable(to), amount: amount });
        else token.transferOut({ payer: address(this), to: to, amount: amount });

        emit Withdrawn(token, account, amount, to);

        return amount;
    }

    function _validAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    modifier authorised(address account) {
        if (msg.sender != account) _checkRole(CONTANGO_ROLE, msg.sender);
        _;
    }

    receive() external payable {
        if (msg.sender != address(nativeToken)) revert SenderIsNotNativeToken(msg.sender, address(nativeToken));
    }

}

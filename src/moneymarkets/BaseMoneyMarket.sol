//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../interfaces/IContango.sol";
import "../libraries/Errors.sol";
import "../libraries/ERC20Lib.sol";

import "./interfaces/IMoneyMarket.sol";

abstract contract BaseMoneyMarket is IMoneyMarket {

    using Address for address payable;
    using ERC20Lib for *;

    MoneyMarketId public immutable moneyMarketId;
    IContango public immutable contango;

    constructor(MoneyMarketId _moneyMarketId, IContango _contango) {
        moneyMarketId = _moneyMarketId;
        contango = _contango;
    }

    function initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) external override onlyContango {
        if (MoneyMarketId.unwrap(positionId.getMoneyMarket()) != MoneyMarketId.unwrap(moneyMarketId)) revert InvalidMoneyMarketId();
        _initialise(positionId, collateralAsset, debtAsset);
    }

    function lend(PositionId positionId, IERC20 asset, uint256 amount) external override onlyContango returns (uint256 lent) {
        if (amount == 0) return 0;
        uint256 balanceBefore = _collateralBalance(positionId, asset);
        lent = _lend(positionId, asset, amount, msg.sender, balanceBefore);
        emit Lent(positionId, asset, lent, balanceBefore);
    }

    function withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to)
        external
        override
        onlyContango
        returns (uint256 withdrawn)
    {
        if (amount == 0) return 0;
        uint256 balanceBefore = _collateralBalance(positionId, asset);
        if (balanceBefore == 0) return 0;
        withdrawn = _withdraw(positionId, asset, amount, to, balanceBefore);
        emit Withdrawn(positionId, asset, withdrawn, balanceBefore);
    }

    function borrow(PositionId positionId, IERC20 asset, uint256 amount, address to)
        external
        override
        onlyContango
        returns (uint256 borrowed)
    {
        if (amount == 0) return 0;
        uint256 balanceBefore = _debtBalance(positionId, asset);
        borrowed = _borrow(positionId, asset, amount, to, balanceBefore);
        emit Borrowed(positionId, asset, borrowed, balanceBefore);
    }

    function repay(PositionId positionId, IERC20 asset, uint256 amount) external override onlyContango returns (uint256 repaid) {
        if (amount == 0) return 0;
        uint256 balanceBefore = _debtBalance(positionId, asset);
        if (balanceBefore == 0) return 0;
        repaid = _repay(positionId, asset, amount, msg.sender, balanceBefore);
        emit Repaid(positionId, asset, repaid, balanceBefore);
    }

    function claimRewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset, address to) external override onlyContango {
        _claimRewards(positionId, collateralAsset, debtAsset, to);
        emit RewardsClaimed(positionId, to);
    }

    function retrieve(PositionId positionId, IERC20 token) external override returns (uint256 amount) {
        if (contango.positionFactory().moneyMarket(positionId) != this) revert InvalidPositionId(positionId);
        PositionNFT positionNFT = contango.positionNFT();
        address owner = positionNFT.exists(positionId) ? positionNFT.positionOwner(positionId) : contango.lastOwner(positionId);

        // If we allow any ERC20, an attacker may transfer collateral tokens, not a security problem, but 1x positions suddenly being empty wouldn't be nice
        if (IERC20(address(0)) != token && !contango.vault().isTokenSupported(token)) revert TokenCantBeRetrieved(token);

        if (token == IERC20(address(0))) {
            amount = address(this).balance;
            payable(owner).sendValue(amount);
        } else {
            amount = token.transferBalance(owner);
        }
        emit Retrieved(positionId, token, amount);
    }

    function collateralBalance(PositionId positionId, IERC20 asset) external override returns (uint256) {
        return _collateralBalance(positionId, asset);
    }

    function debtBalance(PositionId positionId, IERC20 asset) external override returns (uint256) {
        return _debtBalance(positionId, asset);
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IMoneyMarket).interfaceId;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal virtual;

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256 currentBalance)
        internal
        virtual
        returns (uint256 actualAmount);

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256 currentBalance)
        internal
        virtual
        returns (uint256 actualAmount);

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256 currentBalance)
        internal
        virtual
        returns (uint256 actualAmount);

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256 currentBalance)
        internal
        virtual
        returns (uint256 actualAmount);

    function _claimRewards(PositionId, IERC20, IERC20, address) internal virtual {
        // Nothing to do here if the market does not implement rewards
    }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal virtual returns (uint256 balance);

    function _debtBalance(PositionId positionId, IERC20 asset) internal virtual returns (uint256 balance);

    modifier onlyContango() {
        if (msg.sender != address(contango)) revert Unauthorised(msg.sender);
        _;
    }

}

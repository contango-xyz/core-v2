//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../interfaces/IContango.sol";
import "../interfaces/IContangoOracle.sol";
import "./interfaces/IFlashBorrowProvider.sol";
import "./interfaces/IMoneyMarketView.sol";

contract ContangoLens is AccessControlUpgradeable, UUPSUpgradeable, IContangoOracle {

    event MoneyMarketViewRegistered(MoneyMarketId indexed mm, IMoneyMarketView indexed moneyMarketView);

    error CallFailed(address target, bytes4 selector);
    error InvalidMoneyMarket(MoneyMarketId mm);

    struct BorrowingLending {
        uint256 borrowing;
        uint256 lending;
    }

    struct TokenMetadata {
        string name;
        string symbol;
        uint8 decimals;
        uint256 unit;
    }

    struct MetaData {
        Instrument instrument;
        Balances balances;
        Balances balancesUSD;
        Prices prices;
        Prices pricesUSD;
        uint256 ltv;
        uint256 liquidationThreshold;
        BorrowingLending rates;
        BorrowingLending liquidity;
        Reward[] borrowingRewards;
        Reward[] lendingRewards;
        bytes irmRaw;
        AvailableActions[] availableActions;
        Limits limits;
        uint256 fee; // Deprecated
        bool supportsFlashBorrow;
        TokenMetadata baseToken;
        TokenMetadata quoteToken;
    }

    IContango public immutable contango;
    PositionNFT public immutable positionNFT;
    mapping(MoneyMarketId mmId => IMoneyMarketView mmv) public moneyMarketViews;

    constructor(IContango _contango) {
        contango = _contango;
        positionNFT = _contango.positionNFT();
    }

    function initialize(Timelock timelock) public initializer {
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
    }

    function setMoneyMarketView(IMoneyMarketView immv) public onlyRole(OPERATOR_ROLE) {
        MoneyMarketId mm = immv.moneyMarketId();
        moneyMarketViews[mm] = immv;
        emit MoneyMarketViewRegistered(mm, immv);
    }

    function moneyMarketId(PositionId positionId) public view returns (MoneyMarketId) {
        return moneyMarketView(positionId).moneyMarketId();
    }

    function moneyMarketId(MoneyMarketId mmId) public view returns (MoneyMarketId) {
        return moneyMarketView(mmId).moneyMarketId();
    }

    function moneyMarketName(PositionId positionId) public view returns (string memory) {
        return moneyMarketView(positionId).moneyMarketName();
    }

    function moneyMarketName(MoneyMarketId mmId) public view returns (string memory) {
        return moneyMarketView(mmId).moneyMarketName();
    }

    function balances(PositionId positionId) public returns (Balances memory balances_) {
        return positionNFT.exists(positionId) ? moneyMarketView(positionId).balances(positionId) : balances_;
    }

    function prices(PositionId positionId) public view returns (Prices memory prices_) {
        return moneyMarketView(positionId).prices(positionId);
    }

    function balancesUSD(PositionId positionId) public returns (Balances memory balancesUSD_) {
        return positionNFT.exists(positionId) ? moneyMarketView(positionId).balancesUSD(positionId) : balancesUSD_;
    }

    function priceInNativeToken(PositionId positionId, IERC20 asset) public view returns (uint256 price_) {
        return moneyMarketView(positionId).priceInNativeToken(asset);
    }

    function priceInNativeToken(MoneyMarketId mmId, IERC20 asset) public view returns (uint256 price_) {
        return moneyMarketView(mmId).priceInNativeToken(asset);
    }

    function priceInUSD(PositionId positionId, IERC20 asset) public view returns (uint256 price_) {
        return moneyMarketView(positionId).priceInUSD(asset);
    }

    function priceInUSD(MoneyMarketId mmId, IERC20 asset) public view returns (uint256 price_) {
        return moneyMarketView(mmId).priceInUSD(asset);
    }

    function baseQuoteRate(PositionId positionId) public view returns (uint256) {
        return moneyMarketView(positionId).baseQuoteRate(positionId);
    }

    function thresholds(PositionId positionId) public view returns (uint256 ltv, uint256 liquidationThreshold) {
        return moneyMarketView(positionId).thresholds(positionId);
    }

    function liquidity(PositionId positionId) public view returns (uint256 borrowing, uint256 lending) {
        return moneyMarketView(positionId).liquidity(positionId);
    }

    function rates(PositionId positionId) public view returns (uint256 borrowing, uint256 lending) {
        return moneyMarketView(positionId).rates(positionId);
    }

    function irmRaw(PositionId positionId) external returns (bytes memory data) {
        return moneyMarketView(positionId).irmRaw(positionId);
    }

    function rewards(PositionId positionId) public returns (Reward[] memory borrowing, Reward[] memory lending) {
        return moneyMarketView(positionId).rewards(positionId);
    }

    function availableActions(PositionId positionId) external returns (AvailableActions[] memory available) {
        return moneyMarketView(positionId).availableActions(positionId);
    }

    function limits(PositionId positionId) external view returns (Limits memory limits_) {
        return moneyMarketView(positionId).limits(positionId);
    }

    function moneyMarketView(PositionId positionId) public view returns (IMoneyMarketView moneyMarketView_) {
        return moneyMarketView(positionId.getMoneyMarket());
    }

    function moneyMarketView(MoneyMarketId mmId) public view returns (IMoneyMarketView moneyMarketView_) {
        moneyMarketView_ = moneyMarketViews[mmId];
        if (address(moneyMarketView_) == address(0)) revert InvalidMoneyMarket(mmId);
    }

    function leverage(PositionId positionId) public returns (uint256 leverage_) {
        if (!positionNFT.exists(positionId)) return 0;

        Instrument memory instrument = contango.instrument(positionId.getSymbol());

        Balances memory _balances = balances(positionId);
        Prices memory _prices = prices(positionId);
        uint256 collateralValue = _balances.collateral * _prices.collateral / instrument.baseUnit;
        uint256 debtValue = _balances.debt * _prices.debt / instrument.quoteUnit;

        leverage_ = collateralValue * WAD / (collateralValue - debtValue);
    }

    function netRate(PositionId positionId) public returns (int256 netRate_) {
        if (!positionNFT.exists(positionId)) return 0;

        (uint256 borrowing, uint256 lending) = rates(positionId);
        netRate_ = int256(lending) - int256(borrowing * WAD / leverage(positionId));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    function metaData(PositionId positionId) external returns (MetaData memory metaData_) {
        Instrument memory instrument = contango.instrument(positionId.getSymbol());
        IMoneyMarketView mmv = moneyMarketView(positionId);
        metaData_.instrument = instrument;
        if (positionNFT.exists(positionId)) {
            metaData_.balances = mmv.balances(positionId);
            metaData_.balancesUSD = mmv.balancesUSD(positionId);
        }
        metaData_.prices = mmv.prices(positionId);
        metaData_.pricesUSD.collateral = mmv.priceInUSD(instrument.base);
        metaData_.pricesUSD.debt = mmv.priceInUSD(instrument.quote);
        metaData_.pricesUSD.unit = WAD;
        (metaData_.ltv, metaData_.liquidationThreshold) = mmv.thresholds(positionId);
        (metaData_.rates.borrowing, metaData_.rates.lending) = mmv.rates(positionId);
        (metaData_.liquidity.borrowing, metaData_.liquidity.lending) = mmv.liquidity(positionId);
        (metaData_.borrowingRewards, metaData_.lendingRewards) = mmv.rewards(positionId);
        metaData_.irmRaw = mmv.irmRaw(positionId);
        metaData_.availableActions = mmv.availableActions(positionId);
        metaData_.limits = mmv.limits(positionId);
        metaData_.supportsFlashBorrow =
            contango.positionFactory().moneyMarket(positionId.getMoneyMarket()).supportsInterface(type(IFlashBorrowProvider).interfaceId);
        metaData_.baseToken = _tokenMetadata(instrument.base);
        metaData_.quoteToken = _tokenMetadata(instrument.quote);
    }

    function _tokenMetadata(IERC20 token) internal view returns (TokenMetadata memory tokenMetadata_) {
        tokenMetadata_.name = _tryString(token, token.name);
        tokenMetadata_.symbol = _tryString(token, token.symbol);
        tokenMetadata_.decimals = token.decimals();
        tokenMetadata_.unit = 10 ** tokenMetadata_.decimals;
    }

    function _tryString(IERC20 token, function () external view returns (string memory) f) private view returns (string memory) {
        (bool success, bytes memory result) = address(token).staticcall(abi.encodeWithSelector(f.selector));
        if (!success) revert CallFailed(address(token), f.selector);
        return result.length > 32 ? abi.decode(result, (string)) : bytes32ToString(abi.decode(result, (bytes32)));
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) i++;
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

}

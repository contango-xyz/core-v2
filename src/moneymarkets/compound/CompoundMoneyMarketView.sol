//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../libraries/ERC20Lib.sol";
import "../../libraries/Arrays.sol";

import "../BaseMoneyMarketView.sol";

import "./dependencies/IUniswapAnchoredView.sol";
import "./dependencies/IComptroller.sol";
import "./CompoundReverseLookup.sol";

import { IAggregatorV2V3 } from "../../dependencies/Chainlink.sol";

contract CompoundMoneyMarketView is BaseMoneyMarketView {

    struct IRMData {
        uint256 multiplierPerBlock;
        uint256 baseRatePerBlock;
        uint256 jumpMultiplierPerBlock;
        uint256 kink;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 reserveFactorMantissa;
        uint256 cTokenBalance;
        uint256 blocksPerDay;
    }

    using ERC20Lib for IERC20;
    using Math for uint256;

    CompoundReverseLookup public immutable reverseLookup;
    IComptroller public immutable comptroller;
    address public immutable rewardsTokenOracle;

    constructor(
        MoneyMarketId _moneyMarketId,
        string memory _moneyMarketName,
        IContango _contango,
        CompoundReverseLookup _reverseLookup,
        address _rewardsTokenOracle,
        IAggregatorV2V3 _nativeUsdOracle
    ) BaseMoneyMarketView(_moneyMarketId, _moneyMarketName, _contango, _reverseLookup.nativeToken(), _nativeUsdOracle) {
        reverseLookup = _reverseLookup;
        comptroller = _reverseLookup.comptroller();
        rewardsTokenOracle = _rewardsTokenOracle;
    }

    function _balances(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        virtual
        override
        returns (Balances memory balances_)
    {
        address account = _account(positionId);
        balances_.collateral = _cToken(collateralAsset).balanceOfUnderlying(account);
        balances_.debt = _cToken(debtAsset).borrowBalanceCurrent(account);
    }

    function _oraclePrice(IERC20 asset) internal view virtual override returns (uint256) {
        uint256 unitDivision = 10 ** (18 - asset.decimals());
        return IUniswapAnchoredView(comptroller.oracle()).getUnderlyingPrice(_cToken(asset)) / unitDivision;
    }

    function _oracleUnit() internal view virtual override returns (uint256) {
        return WAD;
    }

    function _thresholds(PositionId, IERC20 collateralAsset, IERC20 /* debtAsset */ )
        internal
        view
        virtual
        override
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        liquidationThreshold = ltv = comptroller.markets(_cToken(collateralAsset)).collateralFactorMantissa;
    }

    function _liquidity(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _borrowingLiquidity(debtAsset);
        lending = _lendingLiquidity(collateralAsset);
    }

    function _borrowingLiquidity(IERC20 asset) internal view virtual returns (uint256) {
        ICToken cToken = _cToken(asset);
        uint256 cap = comptroller.borrowCaps(cToken);
        uint256 available = _cTokenBalance(asset, cToken) * 0.95e18 / WAD;
        if (cap == 0) return available;

        uint256 borrowed = cToken.totalBorrows();
        if (borrowed > cap) return 0;

        return Math.min(cap - borrowed, available);
    }

    function _cTokenBalance(IERC20 asset, ICToken cToken) internal view virtual returns (uint256) {
        return asset == nativeToken ? address(cToken).balance : asset.balanceOf(address(cToken));
    }

    function _lendingLiquidity(IERC20 asset) internal view virtual returns (uint256) {
        return asset.totalSupply();
    }

    function _rates(PositionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (uint256 borrowing, uint256 lending)
    {
        borrowing = _apy({ rate: _cToken(debtAsset).borrowRatePerBlock(), perSeconds: _rateFrequency() });
        lending = _apy({ rate: _cToken(collateralAsset).supplyRatePerBlock(), perSeconds: _rateFrequency() });
    }

    function _irmRaw(PositionId, IERC20 collateralAsset, IERC20 debtAsset) internal view virtual override returns (bytes memory data) {
        data = abi.encode(_collectIrmData(collateralAsset), _collectIrmData(debtAsset));
    }

    function _collectIrmData(IERC20 asset) internal view virtual returns (IRMData memory data) {
        ICToken cToken = _cToken(asset);
        data.totalBorrows = cToken.totalBorrows();
        data.totalReserves = cToken.totalReserves();
        data.reserveFactorMantissa = cToken.reserveFactorMantissa();
        data.cTokenBalance = _cTokenBalance(asset, cToken);
        data.blocksPerDay = _blocksPerDay();

        (data.baseRatePerBlock, data.jumpMultiplierPerBlock, data.multiplierPerBlock, data.kink) = _interestRateModelIrmData(cToken);
    }

    function _interestRateModelIrmData(ICToken cToken)
        internal
        view
        virtual
        returns (uint256 baseRatePerBlock, uint256 jumpMultiplierPerBlock, uint256 multiplierPerBlock, uint256 kink)
    {
        ILegacyJumpRateModelV2 irm = cToken.interestRateModel();
        baseRatePerBlock = irm.baseRatePerBlock();
        jumpMultiplierPerBlock = irm.jumpMultiplierPerBlock();
        multiplierPerBlock = irm.multiplierPerBlock();
        kink = irm.kink();
    }

    function _rewards(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        view
        virtual
        override
        returns (Reward[] memory borrowing, Reward[] memory lending)
    {
        Reward memory reward;

        reward = _asRewards(positionId, debtAsset, true);
        if (reward.rate > 0) {
            borrowing = new Reward[](1);
            borrowing[0] = reward;
        }

        reward = _asRewards(positionId, collateralAsset, false);
        if (reward.rate > 0) {
            lending = new Reward[](1);
            lending[0] = reward;
        }

        _updateClaimable(positionId, borrowing, lending);
    }

    function _availableActions(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset)
        internal
        override
        returns (AvailableActions[] memory available)
    {
        ICToken collateralCToken = _cToken(collateralAsset);
        ICToken debtCToken = _cToken(debtAsset);

        available = new AvailableActions[](ACTIONS);
        uint256 count;

        try comptroller.mintAllowed(collateralCToken, address(this), 0) returns (Error error_) {
            (uint256 ltv,) = _thresholds(positionId, collateralAsset, debtAsset);
            if (error_ == Error.NO_ERROR && ltv > 0) available[count++] = AvailableActions.Lend;
        } catch { }

        available[count++] = AvailableActions.Withdraw;
        available[count++] = AvailableActions.Repay;

        comptroller.enterMarkets(toArray(address(debtCToken)));
        try comptroller.borrowAllowed(debtCToken, address(this), 0) returns (Error error_) {
            if (error_ == Error.NO_ERROR) available[count++] = AvailableActions.Borrow;
        } catch { }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(available, count)
        }
    }

    function _updateClaimable(PositionId positionId, Reward[] memory borrowing, Reward[] memory lending) internal view {
        uint256 accrued = comptroller.compAccrued(_account(positionId));
        if (borrowing.length > 0 && lending.length > 0) {
            // When rewards are already accrued, we can't distinguish between borrowing and lending rewards.
            uint256 accruedByBorrowing = accrued / 2;
            uint256 accruedByLending = accrued - accruedByBorrowing;
            borrowing[_findReward(borrowing)].claimable += accruedByBorrowing;
            lending[_findReward(lending)].claimable += accruedByLending;
        } else if (borrowing.length > 0 && lending.length == 0) {
            borrowing[_findReward(borrowing)].claimable += accrued;
        } else if (borrowing.length == 0 && lending.length > 0) {
            lending[_findReward(lending)].claimable += accrued;
        }
    }

    function _findReward(Reward[] memory rewards) internal view returns (uint256 idx) {
        IERC20 rewardsToken = comptroller.getCompAddress();
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].token.token == rewardsToken) return i;
        }
        // solhint-disable-next-line custom-errors
        revert("This should never happen");
    }

    function _blocksPerDay() internal pure virtual returns (uint256) {
        return 60 / 12 * 60 * 24;
    }

    function _rateFrequency() internal pure virtual returns (uint256) {
        return 12;
    }

    function _rewardsTokenUSDPrice() internal view virtual returns (uint256) {
        return uint256(IAggregatorV2V3(rewardsTokenOracle).latestAnswer()) * 1e10;
    }

    function _asRewards(PositionId positionId, IERC20 asset, bool borrowing) internal view virtual returns (Reward memory rewards_) {
        IERC20 rewardsToken = comptroller.getCompAddress();
        ICToken cToken = _cToken(asset);

        rewards_.usdPrice = _rewardsTokenUSDPrice();
        rewards_.token = _asTokenData(rewardsToken);

        uint256 emissionsPerYear =
            (borrowing ? comptroller.compBorrowSpeeds(cToken) : comptroller.compSupplySpeeds(cToken)) * _blocksPerDay() * 365;
        uint256 valueOfEmissions = emissionsPerYear * rewards_.usdPrice / WAD;

        uint256 assetPrice = priceInUSD(asset);
        if (borrowing) {
            uint256 assetsBorrowed = cToken.totalBorrows();
            uint256 valueOfAssetsBorrowed = assetPrice * assetsBorrowed / (10 ** (asset.decimals()));

            rewards_.rate = valueOfEmissions * WAD / valueOfAssetsBorrowed;

            rewards_.claimable = rewards_.rate > 0 && positionId.getNumber() > 0 ? _borrowerAccruedComp(cToken, _account(positionId)) : 0;
        } else {
            uint256 assetSupplied = cToken.totalSupply() * cToken.exchangeRateStored() / (10 ** (asset.decimals()));
            uint256 valueOfAssetsSupplied = assetPrice * assetSupplied / WAD;

            rewards_.rate = valueOfEmissions * WAD / valueOfAssetsSupplied;

            rewards_.claimable = rewards_.rate > 0 && positionId.getNumber() > 0 ? _supplierAccruedComp(cToken, _account(positionId)) : 0;
        }
    }

    function _borrowerAccruedComp(ICToken cToken, address borrower) internal view returns (uint256) {
        uint256 marketBorrowIndex = cToken.borrowIndex();
        IComptroller.CompMarketState memory borrowState = comptroller.compBorrowState(cToken);
        uint256 borrowSpeed = comptroller.compBorrowSpeeds(cToken);
        uint256 blockNumber = _getBlockNumber();
        uint256 deltaBlocks = blockNumber - borrowState.block;

        uint256 borrowIndex = comptroller.compInitialIndex();
        if (deltaBlocks == 0) {
            borrowIndex = borrowState.index;
        } else if (borrowSpeed > 0) {
            uint256 borrowAmount = cToken.totalBorrows() * WAD / marketBorrowIndex;
            uint256 compAccrued = deltaBlocks * borrowSpeed;
            uint256 ratio = borrowAmount > 0 ? compAccrued * 1e36 / borrowAmount : 0;
            borrowIndex = borrowState.index + ratio;
        }

        uint256 borrowerIndex = comptroller.compBorrowerIndex(cToken, borrower);

        if (borrowerIndex == 0 && borrowIndex >= comptroller.compInitialIndex()) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set.
            // Rewards the user with COMP accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = comptroller.compInitialIndex();
        }

        // Calculate change in the cumulative sum of the COMP per borrowed unit accrued
        uint256 deltaIndex = borrowIndex - borrowerIndex;

        uint256 borrowerAmount = cToken.borrowBalanceStored(borrower) * WAD / marketBorrowIndex;

        // Calculate COMP accrued: cTokenAmount * accruedPerBorrowedUnit
        return borrowerAmount * deltaIndex / 1e36;
    }

    function _supplierAccruedComp(ICToken cToken, address supplier) internal view returns (uint256) {
        IComptroller.CompMarketState memory supplyState = comptroller.compSupplyState(cToken);
        uint256 supplySpeed = comptroller.compSupplySpeeds(cToken);
        uint256 blockNumber = _getBlockNumber();
        uint256 deltaBlocks = blockNumber - supplyState.block;

        uint256 supplyIndex = comptroller.compInitialIndex();
        if (deltaBlocks == 0) {
            supplyIndex = supplyState.index;
        } else if (supplySpeed > 0) {
            uint256 supplyTokens = cToken.totalSupply();
            uint256 compAccrued = deltaBlocks * supplySpeed;
            uint256 ratio = supplyTokens > 0 ? compAccrued * 1e36 / supplyTokens : 0;
            supplyIndex = supplyState.index + ratio;
        }

        uint256 supplierIndex = comptroller.compSupplierIndex(cToken, supplier);

        if (supplierIndex == 0 && supplyIndex >= comptroller.compInitialIndex()) {
            // Covers the case where users supplied tokens before the market's supply state index was set.
            // Rewards the user with COMP accrued from the start of when supplier rewards were first
            // set for the market.
            supplierIndex = comptroller.compInitialIndex();
        }

        // Calculate change in the cumulative sum of the COMP per cToken accrued
        uint256 deltaIndex = supplyIndex - supplierIndex;

        uint256 supplierTokens = cToken.balanceOf(supplier);

        // Calculate COMP accrued: cTokenAmount * accruedPerCToken
        return supplierTokens * deltaIndex / 1e36;
    }

    function _getBlockNumber() internal view virtual returns (uint256) {
        return block.number;
    }

    // Visible for tests
    function _cToken(IERC20 asset) public view returns (ICToken) {
        return reverseLookup.cToken(asset);
    }

    // Gets the symbol for an asset, unless it's WETH in which case it returns ETH
    function _symbol(IERC20 asset) private view returns (string memory) {
        return asset == nativeToken ? "ETH" : asset.symbol();
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IFluidVault {

    event LogOperate(
        address indexed user,
        address indexed token,
        int256 supplyAmount,
        int256 borrowAmount,
        address withdrawTo,
        address borrowTo,
        uint256 totalAmounts,
        uint256 exchangePricesAndConfig
    );

    event LogOperate(address user_, uint256 nftId_, int256 colAmt_, int256 debtAmt_, address to_);

    event LogLiquidate(address liquidator_, uint256 colAmt_, uint256 debtAmt_, address to_);

    struct ConstantViews {
        address liquidity;
        address factory;
        address adminImplementation;
        address secondaryImplementation;
        address supplyToken;
        address borrowToken;
        uint8 supplyDecimals;
        uint8 borrowDecimals;
        uint256 vaultId;
        bytes32 liquiditySupplyExchangePriceSlot;
        bytes32 liquidityBorrowExchangePriceSlot;
        bytes32 liquidityUserSupplySlot;
        bytes32 liquidityUserBorrowSlot;
    }

    error FluidLiquidateResult(uint256 colLiquidated, uint256 debtLiquidated);
    error FluidLiquidityCalcsError(uint256 errorId_);
    error FluidSafeTransferError(uint256 errorId_);
    error FluidVaultError(uint256 errorId_);

    function LIQUIDITY() external view returns (address);
    function VAULT_FACTORY() external view returns (address);
    function VAULT_ID() external view returns (uint256);

    function constantsView() external view returns (ConstantViews memory constantsView_);

    function liquidate(uint256 debtAmt_, uint256 colPerUnitDebt_, address to_, bool absorb_)
        external
        payable
        returns (uint256 actualDebtAmt_, uint256 actualColAmt_);

    function operate(uint256 nftId, int256 collateral, int256 debt, address to)
        external
        payable
        returns (uint256 nftId_, int256 newCollateral, int256 newDebt);

    function readFromStorage(bytes32 slot_) external view returns (uint256 result_);

}

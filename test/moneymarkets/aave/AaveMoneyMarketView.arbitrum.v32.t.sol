//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IPoolConfigurator.sol";
import "../AbstractMMV.t.sol";

contract AaveMoneyMarketViewV32Test is AbstractMarketViewTest {

    using Address for *;
    using ERC20Lib for *;
    using { enabled } for AvailableActions[];

    IPool internal pool;
    IPoolConfigurator internal poolConfigurator;

    constructor() AbstractMarketViewTest(MM_AAVE) { }

    function setUp() public {
        super.setUp(Network.Arbitrum, 261_678_099);

        pool = AaveMoneyMarketView(address(sut)).pool();
        poolConfigurator = IPoolConfigurator(env.aaveAddressProvider().getPoolConfigurator());

        vm.mockCall(
            env.aaveAddressProvider().getACLManager(), abi.encodeWithSignature("isPoolAdmin(address)", address(this)), abi.encode(true)
        );
    }

    function testThresholds_NewPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(USDC));

        positionId = encode(instrument.symbol, MM_AAVE, PERP, 0, flagsAndPayload(setBit("", E_MODE), bytes4(uint32(1))));

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.93e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.95e18, 18, "Liquidation threshold");
    }

    function testThresholds_ExistingPosition_EMode() public {
        instrument = env.createInstrument(env.erc20(DAI), env.erc20(USDC));
        positionId = encode(instrument.symbol, MM_AAVE, PERP, 0, flagsAndPayload(setBit("", E_MODE), bytes4(uint32(1))));

        (, positionId,) = env.positionActions().openPosition({
            positionId: positionId,
            quantity: 10_000e18,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        (uint256 ltv, uint256 liquidationThreshold) = sut.thresholds(positionId);

        assertEqDecimal(ltv, 0.93e18, 18, "LTV");
        assertEqDecimal(liquidationThreshold, 0.95e18, 18, "Liquidation threshold");
    }

    function testAvailableActions_BaseFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.base, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BothFrozen() public {
        poolConfigurator.setReserveFreeze(instrument.base, true);
        poolConfigurator.setReserveFreeze(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_BasePaused() public {
        poolConfigurator.setReservePause(instrument.base, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuotePaused() public {
        poolConfigurator.setReservePause(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertFalse(availableActions.enabled(AvailableActions.Repay), "Repay should be disabled");
    }

    function testAvailableActions_BothPaused() public {
        poolConfigurator.setReservePause(instrument.base, true);
        poolConfigurator.setReservePause(instrument.quote, true);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertEq(availableActions.length, 0, "No available actions");
    }

    function testAvailableActions_BaseCollateralDisabled() public {
        (,, positionId) = env.createInstrumentAndPositionId(env.token(LUSD), env.token(USDC), mm);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertFalse(availableActions.enabled(AvailableActions.Lend), "Lend should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Borrow), "Borrow should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

    function testAvailableActions_QuoteBorrowingDisabled() public {
        poolConfigurator.setReserveBorrowing(instrument.quote, false);

        AvailableActions[] memory availableActions = sut.availableActions(positionId);
        assertTrue(availableActions.enabled(AvailableActions.Lend), "Lend should be enabled");
        assertTrue(availableActions.enabled(AvailableActions.Withdraw), "Withdraw should be enabled");
        assertFalse(availableActions.enabled(AvailableActions.Borrow), "Borrow should be disabled");
        assertTrue(availableActions.enabled(AvailableActions.Repay), "Repay should be enabled");
    }

}

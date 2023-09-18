//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "src/core/FeeManager.sol";

import "../../BaseTest.sol";
import "../../TestSetup.t.sol";

contract FeeManagerTest is IFeeManagerEvents, BaseTest {

    Env internal env;
    TestInstrument internal instrument;
    address internal contango;
    IVault internal vault;
    IReferralManager internal referralManager;

    IFeeManager internal sut;

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();
        instrument = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        contango = address(env.contango());
        vault = env.vault();

        sut = env.feeManager();
        referralManager = sut.referralManager();
    }

    function testApplyFee() public {
        // given
        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        Currency expectedFeeCcy = Currency.Base;
        uint256 expectedFee = 0.01 ether;

        env.dealAndApprove(instrument.base, contango, expectedFee, address(sut));

        vm.expectEmit(true, true, true, true);
        emit FeePaid({
            positionId: positionId,
            trader: TRADER,
            referrer: address(0),
            referrerAmount: 0,
            traderRebate: 0,
            protocolFee: expectedFee,
            feeCcy: expectedFeeCcy
        });

        // when
        vm.prank(contango);
        (uint256 fee, Currency feeCcy) = sut.applyFee(TRADER, positionId, 10 ether);

        // then
        assertEqDecimal(fee, expectedFee, instrument.baseDecimals, "fee");
        assertEq(uint8(feeCcy), uint8(expectedFeeCcy), "feeCcy");

        assertEqDecimal(instrument.base.balanceOf(contango), 0, instrument.baseDecimals, "contango base balance");
        assertEqDecimal(vault.balanceOf(instrument.base, TREASURY), expectedFee, instrument.baseDecimals, "treasury vault base balance");
    }

    function testApplyFeeWithReferral() public {
        // given
        vm.prank(TIMELOCK_ADDRESS);
        referralManager.setRewardsAndRebates({ referrerReward: 0.3e4, traderRebate: 0.2e4 });

        bytes32 code = keccak256("code");
        vm.prank(TRADER2);
        referralManager.registerReferralCode(code);

        vm.prank(TRADER);
        referralManager.setTraderReferralByCode(code);

        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, MM_AAVE, PERP, 0);

        Currency expectedFeeCcy = Currency.Base;
        uint256 expectedFee = 0.01 ether;
        uint256 expectedReferrerAmount = 0.003 ether;
        uint256 expectedTraderRebate = 0.002 ether;
        uint256 expectedProtocolFee = 0.005 ether;

        env.dealAndApprove(instrument.base, contango, expectedFee, address(sut));

        vm.expectEmit(true, true, true, true);
        emit FeePaid({
            positionId: positionId,
            trader: TRADER,
            referrer: TRADER2,
            referrerAmount: expectedReferrerAmount,
            traderRebate: expectedTraderRebate,
            protocolFee: expectedProtocolFee,
            feeCcy: expectedFeeCcy
        });

        // when
        vm.prank(contango);
        (uint256 fee, Currency feeCcy) = sut.applyFee(TRADER, positionId, 10 ether);

        // then
        assertEqDecimal(fee, expectedFee, instrument.baseDecimals, "fee");
        assertEq(uint8(feeCcy), uint8(expectedFeeCcy), "feeCcy");

        assertEqDecimal(instrument.base.balanceOf(contango), 0, instrument.baseDecimals, "contango base balance");
        assertEqDecimal(
            vault.balanceOf(instrument.base, TRADER2),
            expectedReferrerAmount,
            instrument.baseDecimals,
            "trader2 (referrer) vault base balance"
        );
        assertEqDecimal(
            vault.balanceOf(instrument.base, TRADER), expectedTraderRebate, instrument.baseDecimals, "trader vault base balance"
        );
        assertEqDecimal(
            vault.balanceOf(instrument.base, TREASURY), expectedProtocolFee, instrument.baseDecimals, "treasury vault base balance"
        );
    }

    function testPermissions() public {
        expectAccessControl(address(this), CONTANGO_ROLE);
        sut.applyFee(address(0), PositionId.wrap(""), 0 ether);
    }

}

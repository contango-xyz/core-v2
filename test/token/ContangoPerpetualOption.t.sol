//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ContangoPerpetualOption, DIAOracleV2, SD59x18, intoUint256, sd, uMAX_SD59x18 } from "src/token/ContangoPerpetualOption.sol";
import { ContangoToken } from "src/token/ContangoToken.sol";
import { BURNER_ROLE } from "src/libraries/Roles.sol";

contract ContangoPerpetualOptionTest is BaseTest {

    // Google Sheets don't get to 18 decimals precision
    uint256 constant TOLERANCE = 10_000;

    address internal tangoOracle = makeAddr("DIAOracleV2");

    Env internal env;
    ContangoPerpetualOption internal sut;

    ContangoToken internal tango;
    IERC20 internal usdc;
    address internal treasury = makeAddr("treasury");
    address internal minter = makeAddr("minter");

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init();

        tango = new ContangoToken(treasury);

        uint256 maxSupply = tango.MAX_SUPPLY();
        vm.prank(treasury);
        tango.mint(treasury, maxSupply);

        address impl = address(new ContangoPerpetualOption(treasury, DIAOracleV2(tangoOracle), tango));
        sut = ContangoPerpetualOption(
            address(new ERC1967Proxy(impl, abi.encodeWithSelector(ContangoPerpetualOption.initialize.selector, TIMELOCK)))
        );
        usdc = sut.USDC();

        vm.startPrank(treasury);
        sut.grantRole(EMERGENCY_BREAK_ROLE, treasury);
        sut.grantRole(RESTARTER_ROLE, treasury);
        vm.stopPrank();
    }

    function test_initialize() public view invariant {
        assertEq(sut.name(), "Contango Perpetual Option");
        assertEq(sut.symbol(), "oTANGO");
        assertEq(sut.decimals(), 18, "decimals");
        assertEq(sut.totalSupply(), 0, "totalSupply");

        assertEqDecimal(SD59x18.unwrap(sut.TANGO_SEED_PRICE()), 0.045e18, 18, "TANGO_SEED_PRICE");
        assertEqDecimal(SD59x18.unwrap(sut.MAX_DISCOUNT()), 0.75e18, 18, "MAX_DISCOUNT");
        assertEqDecimal(SD59x18.unwrap(sut.START_FLAT()), 1e18, 18, "START_FLAT");

        assertEqDecimal(SD59x18.unwrap(sut.A()), 0.241850228606226958e18, 18, "A");
        assertEqDecimal(SD59x18.unwrap(sut.B()), 0.749999999999999998e18, 18, "B");
    }

    // https://docs.google.com/spreadsheets/d/1nz4ubutD5XsvtgsADgaFGqOTS2XZjOPdhVnbh4Se7Jw/edit#gid=1048920014
    function test_previewExercise() public {
        test_previewExercise({ tangoPrice: 0.01e8, expDiscount: -0.777777777777777778e18, expStrikePrice: 0.045e18 });
        test_previewExercise({ tangoPrice: 0.045e8, expDiscount: 0.0e18, expStrikePrice: 0.045e18 });
        test_previewExercise({ tangoPrice: 0.05e8, expDiscount: 0.0254814647979152e18, expStrikePrice: 0.0487259267601042e18 });
        test_previewExercise({ tangoPrice: 0.075e8, expDiscount: 0.123543293885723e18, expStrikePrice: 0.0657342529585708e18 });
        test_previewExercise({ tangoPrice: 0.1e8, expDiscount: 0.1931192688741e18, expStrikePrice: 0.08068807311259e18 });
        test_previewExercise({ tangoPrice: 0.2e8, expDiscount: 0.360757072950284e18, expStrikePrice: 0.127848585409943e18 });
        test_previewExercise({ tangoPrice: 0.3e8, expDiscount: 0.458818902038092e18, expStrikePrice: 0.162354329388572e18 });
        test_previewExercise({ tangoPrice: 0.4e8, expDiscount: 0.528394877026469e18, expStrikePrice: 0.188642049189413e18 });
        test_previewExercise({ tangoPrice: 0.5e8, expDiscount: 0.582362195923816e18, expStrikePrice: 0.208818902038092e18 });
        test_previewExercise({ tangoPrice: 0.6e8, expDiscount: 0.626456706114277e18, expStrikePrice: 0.224125976331434e18 });
        test_previewExercise({ tangoPrice: 0.7e8, expDiscount: 0.663738083270304e18, expStrikePrice: 0.235383341710787e18 });
        test_previewExercise({ tangoPrice: 0.8e8, expDiscount: 0.696032681102653e18, expStrikePrice: 0.243173855117878e18 });
        test_previewExercise({ tangoPrice: 0.9e8, expDiscount: 0.724518535202085e18, expStrikePrice: 0.247933318318124e18 });
        test_previewExercise({ tangoPrice: 1.0e8, expDiscount: 0.75e18, expStrikePrice: 0.25e18 });
        test_previewExercise({ tangoPrice: 1.1e8, expDiscount: 0.75e18, expStrikePrice: 0.275e18 });
        test_previewExercise({ tangoPrice: 1.2e8, expDiscount: 0.75e18, expStrikePrice: 0.3e18 });

        // vm.prank(treasury);
        // sut.updateFloorPrice(sd(0.3e18));
        // test_previewExercise({ tangoPrice: 0.25e8, expDiscount: 0.0e18, expStrikePrice: 0.3e18 });
    }

    function test_previewExercise(uint256 tangoPrice, int256 expDiscount, uint256 expStrikePrice) internal invariant {
        _mockTangoPrice(tangoPrice);
        (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost) = sut.previewExercise(sd(10e18));

        assertEqDecimal(tangoPrice_.intoUint256(), tangoPrice * 1e10, 18, "tango price");
        assertApproxEqAbsDecimal(discount.intoInt256(), expDiscount, TOLERANCE, 18, "discount");
        assertApproxEqAbsDecimal(discountedPrice.intoUint256(), expStrikePrice, TOLERANCE, 18, "redemption");
        assertApproxEqAbsDecimal(cost, (expStrikePrice * 10) / 1e12, TOLERANCE, 6, "cost");
    }

    function test_fuzz_previewExercise(SD59x18 tangoPriceE18, SD59x18 amount) public {
        // Bound the input from almost 0 to 2^128 - 1 which is the max price the oracle could return as per the type system
        tangoPriceE18 = sd(bound(tangoPriceE18.intoInt256(), 0.000001e18, int256(uint256(type(uint128).max))));
        amount = sd(bound(amount.intoInt256(), 1e18, int256(uint256(type(uint128).max))));

        uint256 tangoPriceE8 = tangoPriceE18.intoUint256() / 1e10;
        _mockTangoPrice(tangoPriceE8);
        uint256 tangoPriceE8_18 = tangoPriceE8 * 1e10;
        (SD59x18 tangoPriceE8_18_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost) = sut.previewExercise(amount);

        assertEqDecimal(tangoPriceE8_18_.intoUint256(), tangoPriceE8_18, 18, "tangoPrice");

        if (tangoPriceE18 <= sut.floorPrice()) {
            assertEqDecimal(discount.intoInt256(), (tangoPriceE8_18_ / sut.floorPrice()).intoInt256() - 1e18, 18, "no discount");
            assertEqDecimal(discountedPrice.intoUint256(), sut.floorPrice().intoUint256(), 18, "floor price redemption");
        } else if (tangoPriceE18 >= sut.START_FLAT()) {
            assertEqDecimal(discount.intoUint256(), sut.MAX_DISCOUNT().intoUint256(), 18, "max discount");
            assertEqDecimal(discountedPrice.intoUint256(), (tangoPriceE8_18_ * (sd(1e18) - discount)).intoUint256(), 18, "best redemption");
        } else {
            assertGtDecimal(discount.intoUint256(), 0, 18, "discount");
            assertLtDecimal(discount.intoUint256(), sut.MAX_DISCOUNT().intoUint256(), 18, "discount");
            assertEqDecimal(discountedPrice.intoUint256(), (tangoPriceE8_18_ * (sd(1e18) - discount)).intoUint256(), 18, "redemption");
        }

        assertApproxEqAbsDecimal(cost, (discountedPrice * amount).intoUint256() / 1e12, 1, 6, "cost");
        assertGtDecimal(cost, 0, 18, "cost is zero");
    }

    function test_Fund() public invariant {
        uint256 amount = 150_000_000e18;

        _fund(amount);

        assertEqDecimal(sut.totalSupply(), amount, 18, "totalSupply");
        assertEqDecimal(sut.balanceOf(treasury), sut.totalSupply(), 18, "treasury balance");
        assertEqDecimal(tango.balanceOf(address(sut)), sut.totalSupply(), 18, "tango balance");

        vm.prank(treasury);
        sut.pause();
        vm.expectRevert("Pausable: paused");
        sut.fund(1);
    }

    function test_Burn() public invariant {
        uint256 amount = 150_000_000e18;

        _fund(amount);

        assertEqDecimal(sut.totalSupply(), amount, 18, "totalSupply");
        assertEqDecimal(sut.balanceOf(treasury), amount, 18, "treasury balance");
        assertEqDecimal(tango.balanceOf(address(sut)), amount, 18, "tango balance");
        uint256 treasuryBalance = tango.balanceOf(treasury);

        expectAccessControl(address(this), BURNER_ROLE);
        sut.burn(100e18);

        vm.prank(treasury);
        sut.burn(100e18);

        assertEqDecimal(sut.totalSupply(), amount - 100e18, 18, "totalSupply");
        assertEqDecimal(sut.balanceOf(treasury), amount - 100e18, 18, "treasury balance");
        assertEqDecimal(tango.balanceOf(address(sut)), amount - 100e18, 18, "tango balance");
        assertEqDecimal(tango.balanceOf(treasury), treasuryBalance + 100e18, 18, "tango treasury balance");
    }

    function test_exercise_approval() public invariant {
        _mockTangoPrice(0.1e8);
        _fund(10_000e18);

        address user = makeAddr("user");
        vm.prank(treasury);
        sut.transfer(user, 1000e18);
        env.dealAndApprove(usdc, user, 100e6, address(sut));

        assertEqDecimal(sut.balanceOf(user), 1000e18, 18, "intial oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 100e6, 6, "intial usd balance");
        assertEqDecimal(tango.balanceOf(user), 0, 18, "intial tango balance");

        vm.prank(user);
        sut.exercise(sd(100e18), sd(0.09e18));

        assertEqDecimal(sut.balanceOf(user), 900e18, 18, "final oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 91.931192e6, 6, "final usd balance");
        assertEqDecimal(tango.balanceOf(user), 100e18, 18, "final tango balance");
    }

    function test_exercise_permit() public invariant {
        _mockTangoPrice(0.1e8);
        _fund(10_000e18);

        (address user, uint256 userPK) = makeAddrAndKey("user");
        vm.prank(treasury);
        sut.transfer(user, 1000e18);
        EIP2098Permit memory permit = env.dealAndPermit(usdc, user, userPK, 100e6, address(sut));

        assertEqDecimal(sut.balanceOf(user), 1000e18, 18, "intial oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 100e6, 6, "intial usd balance");
        assertEqDecimal(tango.balanceOf(user), 0, 18, "intial tango balance");

        vm.prank(user);
        sut.exercise(sd(100e18), sd(0.09e18), permit);

        assertEqDecimal(sut.balanceOf(user), 900e18, 18, "final oTango balance");
        assertEqDecimal(usdc.balanceOf(user), 91.931192e6, 6, "final usd balance");
        assertEqDecimal(tango.balanceOf(user), 100e18, 18, "final tango balance");
    }

    function test_validations() public invariant {
        address user = makeAddr("user");
        _fund(10_000e18);
        vm.prank(treasury);
        sut.transfer(user, 1000e18);

        _mockTangoPrice(0);
        vm.expectRevert(ContangoPerpetualOption.ZeroPrice.selector);
        vm.prank(user);
        sut.exercise(sd(100e18), sd(1e18));

        _mockTangoPrice(0.1e8);
        vm.expectRevert(ContangoPerpetualOption.ZeroCost.selector);
        vm.prank(user);
        sut.exercise(sd(0), sd(1e18));

        vm.prank(treasury);
        sut.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(user);
        sut.exercise(sd(100e18), sd(1e18));

        vm.prank(treasury);
        sut.unpause();
        vm.expectRevert(abi.encodeWithSelector(ContangoPerpetualOption.SlippageCheck.selector, 0.05e18, 0.08068807311259003e18));
        vm.prank(user);
        sut.exercise(sd(100e18), sd(0.05e18));

        expectAccessControl(address(this), "");
        sut.updateFloorPrice(sd(0.3e18));
    }

    function test_tangoPrice() public {
        _mockTangoPrice(0.1e8);
        assertEqDecimal(sut.tangoPrice().intoUint256(), 0.1e18, 18, "tango price");

        vm.mockCall(
            tangoOracle,
            abi.encodeWithSelector(DIAOracleV2.getValue.selector, "TANGO/USD"),
            abi.encode(0.1e8, block.timestamp - 1 days - 10 minutes - 1)
        );
        vm.expectRevert(
            abi.encodeWithSelector(ContangoPerpetualOption.StaleOraclePrice.selector, block.timestamp - 1 days - 10 minutes - 1, 0.1e8)
        );
        sut.tangoPrice();

        vm.mockCall(tangoOracle, abi.encodeWithSelector(DIAOracleV2.getValue.selector, "TANGO/USD"), abi.encode(0, block.timestamp));
        vm.expectRevert(ContangoPerpetualOption.ZeroPrice.selector);
        sut.tangoPrice();
    }

    modifier invariant() {
        _;
        assertEqDecimal(tango.balanceOf(address(sut)), sut.totalSupply(), 18, "tango balance");
    }

    function _fund(uint256 amount) internal {
        vm.startPrank(treasury);
        tango.approve(address(sut), amount);
        sut.fund(amount);
        vm.stopPrank();
    }

    function _mockTangoPrice(uint256 price) internal {
        vm.mockCall(tangoOracle, abi.encodeWithSelector(DIAOracleV2.getValue.selector, "TANGO/USD"), abi.encode(price, block.timestamp));
    }

}

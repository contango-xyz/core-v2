// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Math as MathOZ } from "@openzeppelin/contracts/utils/math/Math.sol";

import "@prb/math/src/SD59x18.sol";

import "../dependencies/DIAOracleV2.sol";
import "../libraries/ERC20Lib.sol";

contract ContangoPerpetualOption is ERC20, ERC20Permit {

    using ERC20Lib for IERC20;

    error StaleOraclePrice(uint256 timestamp, uint256 price);
    error ZeroPrice();
    error ZeroCost();
    error OnlyTreasury();

    event Exercised(address indexed account, SD59x18 amount, SD59x18 tangoPrice, SD59x18 discount, SD59x18 discountedPrice, uint256 cost);

    // Taken from Silo's DiaOracleV2 adapter
    uint256 public constant ORACLE_TOLERANCE = 1 days + 10 minutes;
    IERC20 public constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    uint256 public constant USDC_UNIT_DIFF = 1e12;
    int256 public constant DIA_UNIT_DIFF = 1e10;

    SD59x18 public constant TANGO_SEED_PRICE = SD59x18.wrap(0.045e18);
    SD59x18 public constant MAX_DISCOUNT = SD59x18.wrap(0.75e18);
    SD59x18 public constant START_FLAT = SD59x18.wrap(1e18);
    SD59x18 public immutable A;
    SD59x18 public immutable B;

    address public immutable treasury;
    DIAOracleV2 public immutable tangoOracle;
    IERC20 public immutable tango;

    constructor(address _treasury, DIAOracleV2 _tangoOracle, IERC20 _tango)
        ERC20("Contango Perpetual Option", "oTANGO")
        ERC20Permit("Contango Perpetual Option")
    {
        treasury = _treasury;
        tangoOracle = _tangoOracle;
        tango = _tango;

        A = MAX_DISCOUNT / (ln(START_FLAT) - ln(TANGO_SEED_PRICE));
        B = -A * ln(TANGO_SEED_PRICE);
    }

    /// @notice mints oTANGO tokens in exchange for TANGO tokens, this operation can't be undone
    /// Be careful, you're implicitly forfeiting your TANGO tokens and the only way to recover them is by excersising
    /// the oTANGO tokens, for which you'll have to pay at the current oTANGO discount price
    function fund(uint256 amount) public {
        tango.transferOut(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public {
        require(msg.sender == treasury, OnlyTreasury());
        _burn(treasury, amount);
        tango.transferOut(address(this), treasury, amount);
    }

    function previewExercise(SD59x18 amount)
        public
        view
        returns (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost)
    {
        tangoPrice_ = tangoPrice();

        if (tangoPrice_ <= TANGO_SEED_PRICE) {
            discount = ZERO;
            discountedPrice = tangoPrice_;
        } else {
            discount = tangoPrice_ < START_FLAT ? A * ln(tangoPrice_) + B : MAX_DISCOUNT;
            discountedPrice = tangoPrice_ * (UNIT - discount);
        }
        cost = MathOZ.ceilDiv((amount * discountedPrice).intoUint256(), USDC_UNIT_DIFF);

        require(cost > 0, ZeroCost());
    }

    function exercise(SD59x18 amount) public returns (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 discountedPrice, uint256 cost) {
        _burn(msg.sender, amount.intoUint256());

        (tangoPrice_, discount, discountedPrice, cost) = previewExercise(amount);

        USDC.transferOut(msg.sender, treasury, cost);
        tango.transferOut(address(this), msg.sender, amount.intoUint256());

        emit Exercised(msg.sender, amount, tangoPrice_, discount, discountedPrice, cost);
    }

    function exercise(SD59x18 amount, EIP2098Permit calldata permit) public {
        USDC.applyPermit({ permit: permit, owner: msg.sender, spender: address(this) });
        exercise(amount);
    }

    function tangoPrice() public view returns (SD59x18) {
        (uint256 price, uint256 timestamp) = tangoOracle.getValue("TANGO/USD");
        require(price > 0, ZeroPrice());
        require(timestamp + ORACLE_TOLERANCE >= block.timestamp, StaleOraclePrice(timestamp, price));

        // Cast is safe cause price is uint128
        return sd(int256(price) * DIA_UNIT_DIFF);
    }

}

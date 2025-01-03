// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable as AccessControl } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable as Pausable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20Upgradeable as ERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { ERC20PermitUpgradeable as ERC20Permit } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { Math as MathOZ } from "@openzeppelin/contracts/utils/math/Math.sol";

import "@prb/math/src/SD59x18.sol";

import "../dependencies/DIAOracleV2.sol";
import "../libraries/ERC20Lib.sol";
import { EMERGENCY_BREAK_ROLE, RESTARTER_ROLE, BURNER_ROLE } from "../libraries/Roles.sol";

contract ContangoPerpetualOption is ERC20, ERC20Permit, UUPSUpgradeable, AccessControl, Pausable {

    using ERC20Lib for IERC20;

    error StaleOraclePrice(uint256 timestamp, uint256 price);
    error ZeroPrice();
    error ZeroCost();
    error SlippageCheck(SD59x18 max, SD59x18 actual);
    error InvalidFloorPrice(SD59x18 floorPrice);

    event Exercised(address indexed account, SD59x18 amount, SD59x18 tangoPrice, SD59x18 discount, SD59x18 strikePrice, uint256 cost);
    event FloorPriceUpdated(SD59x18 newFloorPrice);

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

    SD59x18 public floorPrice;

    constructor(address _treasury, DIAOracleV2 _tangoOracle, IERC20 _tango) ERC20() ERC20Permit() {
        treasury = _treasury;
        tangoOracle = _tangoOracle;
        tango = _tango;

        A = MAX_DISCOUNT / (ln(START_FLAT) - ln(TANGO_SEED_PRICE));
        B = -A * ln(TANGO_SEED_PRICE);
    }

    function initialize() public initializer {
        __ERC20_init_unchained("Contango Perpetual Option", "oTANGO");
        __ERC20Permit_init_unchained("Contango Perpetual Option");
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(BURNER_ROLE, treasury);
        _grantRole(EMERGENCY_BREAK_ROLE, treasury);
        _grantRole(RESTARTER_ROLE, treasury);
        _updateFloorPrice(TANGO_SEED_PRICE);
    }

    function initialisePermit() public reinitializer(2) {
        __ERC20Permit_init("Contango Perpetual Option");
    }

    function updateFloorPrice(SD59x18 newFloorPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateFloorPrice(newFloorPrice);
    }

    function _updateFloorPrice(SD59x18 newFloorPrice) internal {
        require(newFloorPrice >= TANGO_SEED_PRICE, InvalidFloorPrice(newFloorPrice));
        floorPrice = newFloorPrice;
        emit FloorPriceUpdated(newFloorPrice);
    }

    /// @notice mints oTANGO tokens in exchange for TANGO tokens, this operation can't be undone
    /// Be careful, you're implicitly forfeiting your TANGO tokens and the only way to recover them is by exercising
    /// the oTANGO tokens, for which you'll have to pay at the current oTANGO discount price
    function fund(uint256 amount) public whenNotPaused {
        tango.transferOut(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(treasury, amount);
        tango.transferOut(address(this), treasury, amount);
    }

    function previewExercise(SD59x18 amount)
        public
        view
        returns (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 strikePrice, uint256 cost)
    {
        tangoPrice_ = tangoPrice();

        if (tangoPrice_ <= floorPrice) {
            strikePrice = floorPrice;
            discount = (tangoPrice_ / strikePrice) - UNIT;
        } else {
            discount = tangoPrice_ < START_FLAT ? A * ln(tangoPrice_) + B : MAX_DISCOUNT;
            strikePrice = tangoPrice_ * (UNIT - discount);
        }
        cost = MathOZ.ceilDiv((amount * strikePrice).intoUint256(), USDC_UNIT_DIFF);

        require(cost > 0, ZeroCost());
    }

    function exercise(SD59x18 amount, SD59x18 maxPrice)
        public
        whenNotPaused
        returns (SD59x18 tangoPrice_, SD59x18 discount, SD59x18 strikePrice, uint256 cost)
    {
        _burn(msg.sender, amount.intoUint256());

        (tangoPrice_, discount, strikePrice, cost) = previewExercise(amount);

        require(strikePrice <= maxPrice, SlippageCheck(maxPrice, strikePrice));

        USDC.transferOut(msg.sender, treasury, cost);
        tango.transferOut(address(this), msg.sender, amount.intoUint256());

        emit Exercised(msg.sender, amount, tangoPrice_, discount, strikePrice, cost);
    }

    function exercise(SD59x18 amount, SD59x18 maxPrice, EIP2098Permit calldata permit) public {
        USDC.applyPermit({ permit: permit, owner: msg.sender, spender: address(this) });
        exercise(amount, maxPrice);
    }

    function tangoPrice() public view returns (SD59x18) {
        (uint256 price, uint256 timestamp) = tangoOracle.getValue("TANGO/USD");
        require(price > 0, ZeroPrice());
        require(timestamp + ORACLE_TOLERANCE >= block.timestamp, StaleOraclePrice(timestamp, price));

        // Cast is safe cause price is uint128
        return sd(int256(price) * DIA_UNIT_DIFF);
    }

    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) { }

    function pause() external onlyRole(EMERGENCY_BREAK_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(RESTARTER_ROLE) {
        _unpause();
    }

}

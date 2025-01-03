//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseTest.sol";
import { AddressSet, LibAddressSet } from "../AddressSet.sol";

import { ContangoPerpetualOption, DIAOracleV2, SD59x18, intoUint256, sd, uMAX_SD59x18 } from "src/token/ContangoPerpetualOption.sol";
import { ContangoToken } from "src/token/ContangoToken.sol";

contract ContangoPerpetualOptionInvariantTest is BaseTest {

    address internal tangoOracle = makeAddr("DIAOracleV2");

    ContangoPerpetualOption internal sut;
    ContangoPerpetualOptionHandler internal handler;

    IERC20 internal tango;
    ERC20Mock internal usdc;
    address internal treasury = makeAddr("treasury");

    function setUp() public {
        tango = new ContangoToken(treasury);

        sut = new ContangoPerpetualOption(treasury, DIAOracleV2(tangoOracle), tango);
        handler = new ContangoPerpetualOptionHandler(sut);

        usdc = ERC20Mock(address(sut.USDC()));
        vm.etch(address(sut.USDC()), address(new ERC20Mock()).code);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.fund.selector;
        selectors[1] = handler.exercise.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transfer.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.dust.selector;

        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    // The total supply of oTANGO must be equal to the TANGO locked in the contract.
    function invariant_everyOptionIsAlwaysBacked() public view {
        assertGeDecimal(tango.balanceOf(address(sut)), sut.totalSupply(), 18, "everyOptionIsAlwaysBacked");
    }

    // The total supply of oTANGO must be equal to the sum of all minted oTANGO minus the sum of all exercised oTANGO.
    function invariant_totalSupplyIsAlwaysCorrect() public view {
        assertEqDecimal(sut.totalSupply(), handler.ghost_fundSum() - handler.ghost_exceriseSum(), 18, "totalSupplyIsAlwaysCorrect");
    }

    // The sum of all collected usdc must be equal to the sum of all the cost for exercised oTANGO.
    function invariant_usdcProceedsAddUp() public view {
        assertEqDecimal(usdc.balanceOf(treasury), handler.ghost_costSum(), 18, "usdcProceedsAddUp");
    }

    // The sum of all exercised TANGO balances must be equal to the sum of all burned oTANGO.
    function invariant_excerisedBalances() public {
        uint256 sumOfBalances = handler.reduceActors(0, this.tangoBalanceAcc);
        assertEqDecimal(handler.ghost_exceriseSum(), sumOfBalances, 18, "excersisedBalances");
    }

    // No individual account balance can exceed the oTANGO totalSupply().
    function invariant_depositorBalances() public {
        handler.forEachActor(this.assertAccountBalanceLteTotalSupply);
    }

    function assertAccountBalanceLteTotalSupply(address account) external view {
        assertLe(sut.balanceOf(account), sut.totalSupply());
    }

    function tangoBalanceAcc(uint256 balance, address caller) external view returns (uint256) {
        return balance + tango.balanceOf(caller);
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }

}

contract ContangoPerpetualOptionHandler is TestBase, StdCheats, StdUtils {

    using LibAddressSet for AddressSet;

    ContangoPerpetualOption internal immutable sut;
    address internal immutable treasury;
    ERC20Mock internal usdc;
    address internal tangoOracle;
    IERC20 internal tango;

    uint256 public ghost_fundSum;
    uint256 public ghost_exceriseSum;
    uint256 public ghost_costSum;
    uint256 public ghost_dustSum;

    uint256 public ghost_zeroTransfers;
    uint256 public ghost_zeroTransferFroms;

    constructor(ContangoPerpetualOption _sut) {
        sut = _sut;
        treasury = sut.treasury();
        tangoOracle = address(sut.tangoOracle());
        usdc = ERC20Mock(address(sut.USDC()));
        tango = sut.tango();
    }

    mapping(bytes32 => uint256) public calls;
    AddressSet internal _actors;
    address internal currentActor;

    modifier createActor() {
        if (address(sut) == msg.sender) return;
        if (treasury == msg.sender) return;

        currentActor = msg.sender;
        _actors.add(currentActor);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function fund(uint256 amount) public createActor countCall("fund") {
        amount = _bound(amount, 0, tango.balanceOf(treasury));
        _sendTango(currentActor, amount);

        vm.startPrank(currentActor);
        tango.approve(address(sut), amount);
        sut.fund(amount);
        vm.stopPrank();

        ghost_fundSum += amount;
    }

    function exercise(uint256 actorSeed, uint256 uAmount, uint256 price) public useActor(actorSeed) countCall("exercise") {
        uint256 actorBalance = sut.balanceOf(currentActor);
        if (actorBalance < 0.001e18) return;

        _mockTangoPrice(_bound(price, 0.001e8, 1e8));
        uAmount = _bound(uAmount, 0.001e18, actorBalance);

        SD59x18 amount = sd(int256(uAmount));
        (,, SD59x18 strikePrice, uint256 cost) = sut.previewExercise(amount);

        usdc.mint(currentActor, cost);

        vm.startPrank(currentActor);
        usdc.approve(address(sut), cost);
        sut.exercise(amount, strikePrice);
        vm.stopPrank();

        ghost_exceriseSum += uAmount;
        ghost_costSum += cost;
    }

    function approve(uint256 actorSeed, uint256 spenderSeed, uint256 amount) public useActor(actorSeed) countCall("approve") {
        address spender = _actors.rand(spenderSeed);

        vm.prank(currentActor);
        sut.approve(spender, amount);
    }

    function transfer(uint256 actorSeed, uint256 toSeed, uint256 amount) public useActor(actorSeed) countCall("transfer") {
        address to = _actors.rand(toSeed);

        amount = _bound(amount, 0, sut.balanceOf(currentActor));
        if (amount == 0) ghost_zeroTransfers++;

        vm.prank(currentActor);
        sut.transfer(to, amount);
    }

    function transferFrom(uint256 actorSeed, uint256 fromSeed, uint256 toSeed, bool _approve, uint256 amount)
        public
        useActor(actorSeed)
        countCall("transferFrom")
    {
        address from = _actors.rand(fromSeed);
        address to = _actors.rand(toSeed);

        amount = _bound(amount, 0, sut.balanceOf(from));

        if (_approve) {
            vm.prank(from);
            sut.approve(currentActor, amount);
        } else {
            amount = _bound(amount, 0, sut.allowance(from, currentActor));
        }
        if (amount == 0) ghost_zeroTransferFroms++;

        vm.prank(currentActor);
        sut.transferFrom(from, to, amount);
    }

    function dust(uint256 amount) public countCall("dust") {
        amount = _bound(amount, 0, tango.balanceOf(treasury));
        _sendTango(address(sut), amount);
        ghost_dustSum += amount;
    }

    function _mockTangoPrice(uint256 price) internal {
        vm.mockCall(tangoOracle, abi.encodeWithSelector(DIAOracleV2.getValue.selector, "TANGO/USD"), abi.encode(price, block.timestamp));
    }

    function _sendTango(address actor, uint256 amount) internal {
        vm.prank(treasury);
        tango.transfer(actor, amount);
    }

    function forEachActor(function(address) external func) public {
        return _actors.forEach(func);
    }

    function reduceActors(uint256 acc, function(uint256,address) external returns (uint256) func) public returns (uint256) {
        return _actors.reduce(acc, func);
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("fund", calls["fund"]);
        console.log("exercise", calls["exercise"]);
        console.log("approve", calls["approve"]);
        console.log("transfer", calls["transfer"]);
        console.log("transferFrom", calls["transferFrom"]);
        console.log("dust", calls["dust"]);
        console.log("-------------------");

        console.log("Zero transferFroms:", ghost_zeroTransferFroms);
        console.log("Zero transfers:", ghost_zeroTransfers);
    }

}

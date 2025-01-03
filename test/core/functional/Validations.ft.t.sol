//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../BaseTest.sol";

contract Validations is BaseTest, IContangoEvents, IContangoErrors {

    using SignedMath for *;
    using Address for address payable;

    Env internal env;

    address hacker = address(666);
    IContango contango;
    Maestro maestro;
    address uniswap;

    IERC20 weth;
    IERC20 usdc;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();
        contango = env.contango();
        maestro = env.maestro();
        uniswap = env.uniswap();

        weth = env.token(WETH);
        usdc = env.token(USDC);
    }

    function testPermissions() public {
        expectAccessControl(hacker, OPERATOR_ROLE);
        contango.createInstrument(Symbol.wrap(""), IERC20(address(0)), IERC20(address(0)));

        expectAccessControl(hacker, OPERATOR_ROLE);
        contango.setClosingOnly(Symbol.wrap(""), true);
    }

    function testSetters() public {
        vm.startPrank(TIMELOCK_ADDRESS);
        AccessControlUpgradeable(address(contango)).grantRole(OPERATOR_ROLE, TIMELOCK_ADDRESS);

        vm.expectEmit(true, true, true, true);
        emit InstrumentCreated(WETHUSDC, weth, usdc);
        contango.createInstrument(WETHUSDC, weth, usdc);

        vm.expectRevert(abi.encodeWithSelector(InstrumentAlreadyExists.selector, WETHUSDC));
        contango.createInstrument(WETHUSDC, weth, usdc);

        vm.expectEmit(true, true, true, true);
        emit ClosingOnlySet(WETHUSDC, true);
        contango.setClosingOnly(WETHUSDC, true);

        vm.stopPrank();
    }

    function testCreatePositionPermission() public {
        vm.prank(TIMELOCK_ADDRESS);
        contango.createInstrument(WETHUSDC, weth, usdc);

        TradeParams memory tradeParams;
        tradeParams.positionId = encode(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP, 0, 0);
        tradeParams.quantity = 1 ether;
        ExecutionParams memory execParams;

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.tradeOnBehalfOf(tradeParams, execParams, TRADER);
    }

    function testPositionPermissions() public {
        TestInstrument memory instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: instrument.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        TradeParams memory tradeParams;
        tradeParams.positionId = positionId;
        ExecutionParams memory execParams;

        tradeParams.quantity = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.trade(tradeParams, execParams);

        tradeParams.quantity = -1 ether;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.trade(tradeParams, execParams);

        tradeParams.quantity = 0;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.trade(tradeParams, execParams);

        tradeParams.quantity = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.trade(tradeParams, execParams);

        tradeParams.quantity = -1 ether;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.trade(tradeParams, execParams);

        tradeParams.quantity = 0;
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        maestro.trade(tradeParams, execParams);

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.claimRewards(positionId, address(this));

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.donatePosition(positionId, address(0xb0b));

        // after full close
        skip(1 seconds);
        env.positionActions().closePosition({ positionId: positionId, quantity: type(uint128).max, cashflow: 0, cashflowCcy: Currency.Quote });

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.claimRewards(positionId, address(this));

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        contango.donatePosition(positionId, address(0xb0b));
    }

    function testCallbackPermissions() public {
        Contango.FlashLoanCallback memory cb;
        cb.ep.flashLoanProvider = new TestFLP();
        cb.positionId = env.encoder().encodePositionId(WETHUSDC, MM_AAVE, PERP, 1);

        vm.expectRevert(abi.encodeWithSelector(UnexpectedCallback.selector));
        contango.completeOpenFromFlashLoan({
            initiator: address(contango),
            repayTo: address(0),
            asset: address(0),
            amount: 0,
            fee: 0,
            params: abi.encode(cb)
        });

        vm.expectRevert(abi.encodeWithSelector(NotFlashBorrowProvider.selector, address(this)));
        contango.completeOpenFromFlashBorrow({ asset: IERC20(address(0)), amountOwed: 0, params: abi.encode(cb) });

        vm.expectRevert(abi.encodeWithSelector(UnexpectedCallback.selector));
        contango.completeClose({
            initiator: address(contango),
            repayTo: address(0),
            asset: address(0),
            amount: 0,
            fee: 0,
            params: abi.encode(cb)
        });
    }

    function testIERC7399Response() public {
        TestInstrument memory instrument = env.createInstrument({ baseData: env.erc20(WETH), quoteData: env.erc20(USDC) });
        env.spotStub().stubPrice({
            base: instrument.baseData,
            quote: instrument.quoteData,
            baseUsdPrice: 1000e8,
            quoteUsdPrice: 1e8,
            uniswapFee: 500
        });

        PositionId positionId = env.encoder().encodePositionId(instrument.symbol, MM_EXACTLY, PERP, 0);

        Currency cashflowCcy = Currency.Base;
        TSQuote memory quote = env.positionActions().quoteTrade({
            positionId: positionId,
            quantity: 10 ether,
            cashflow: 4 ether,
            cashflowCcy: cashflowCcy,
            leverage: 0
        });
        env.dealAndApprove(instrument.base, TRADER, uint256(quote.cashflowUsed), address(env.vault()));
        vm.prank(TRADER);
        maestro.deposit(instrument.base, uint256(quote.cashflowUsed));

        IERC7399 flp = new BadFLP(new TestFLP());
        quote.execParams.flashLoanProvider = flp;

        vm.prank(TRADER);
        vm.expectRevert(UnexpectedTrade.selector);
        maestro.trade(quote.tradeParams, quote.execParams);
    }

    function testPauseUnpausePermissions() public {
        expectAccessControl(address(this), EMERGENCY_BREAK_ROLE);
        contango.pause();

        expectAccessControl(address(this), RESTARTER_ROLE);
        contango.unpause();
    }

    function testPause() public {
        TradeParams memory tradeParams;
        ExecutionParams memory execParams;

        vm.prank(TIMELOCK_ADDRESS);
        AccessControlUpgradeable(address(contango)).grantRole(EMERGENCY_BREAK_ROLE, address(this));

        contango.pause();

        vm.expectRevert("Pausable: paused");
        contango.trade(tradeParams, execParams);

        vm.expectRevert("Pausable: paused");
        contango.tradeOnBehalfOf(tradeParams, execParams, address(0));

        vm.expectRevert("Pausable: paused");
        contango.donatePosition(PositionId.wrap(0), address(0));
    }

}

contract BadFLP is IERC7399 {

    IERC7399 public immutable realFLP;

    constructor(IERC7399 _realFLP) {
        realFLP = _realFLP;
    }

    function maxFlashLoan(address asset) external view returns (uint256) {
        return realFLP.maxFlashLoan(asset);
    }

    function flashFee(address asset, uint256 amount) external view returns (uint256) {
        return realFLP.flashFee(asset, amount);
    }

    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    ) external returns (bytes memory) {
        Trade memory trade = abi.decode(realFLP.flash(loanReceiver, asset, amount, data, callback), (Trade));

        // Mess up with the trade
        trade.forwardPrice = 1;

        return abi.encode(trade);
    }

}

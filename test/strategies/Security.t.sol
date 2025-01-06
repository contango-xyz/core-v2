//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";
import "../BaseTest.sol";

import "src/strategies/StrategyBuilder.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

contract StrategiesSecurityTest is BaseTest, GasSnapshot {

    using Address for *;
    using ERC20Lib for *;
    using { positionsUpserted } for Vm.Log[];

    Env internal env;
    IVault internal vault;
    SimpleSpotExecutor internal spotExecutor;
    SwapRouter02 internal router;
    IERC20 internal weth;
    IERC20 internal usdc;
    IERC20 internal dai;
    IERC20 internal wstEth;
    PositionNFT internal positionNFT;

    StrategyBuilder internal sut;

    address internal trader;
    uint256 internal traderPK;

    StepCall[] internal steps;

    address internal hacker = makeAddr("hacker");
    address internal operator = makeAddr("operator");

    function setUp() public {
        env = provider(Network.Arbitrum);
        env.init(195_104_100);

        vault = env.vault();
        trader = env.positionActions().trader();
        traderPK = env.positionActions().traderPk();
        spotExecutor = env.maestro().spotExecutor();
        router = env.uniswapRouter();
        positionNFT = env.positionNFT();

        weth = env.token(WETH);
        usdc = env.token(USDC);
        dai = env.token(DAI);

        sut = env.strategyBuilder();

        env.spotStub().stubPrice({ base: env.erc20(WETH), quote: env.erc20(USDC), baseUsdPrice: 1000e8, quoteUsdPrice: 1e8, uniswapFee: 500 });

        env.spotStub().stubPrice({
            base: env.erc20(USDC),
            quote: env.erc20(DAI),
            baseUsdPrice: 0.999e8,
            quoteUsdPrice: 1.0001e8,
            uniswapFee: 500
        });

        vm.prank(TIMELOCK_ADDRESS);
        sut.grantRole(OPERATOR_ROLE, operator);

        vm.prank(TIMELOCK_ADDRESS);
        sut.grantRole(EMERGENCY_BREAK_ROLE, operator);

        vm.prank(TIMELOCK_ADDRESS);
        sut.grantRole(RESTARTER_ROLE, operator);
    }

    function testCanNotBeUsedWhenPaused() public {
        expectAccessControl(hacker, EMERGENCY_BREAK_ROLE);
        sut.pause();

        vm.prank(operator);
        sut.pause();

        vm.expectRevert("Pausable: paused");
        sut.process(steps);

        vm.prank(operator);
        sut.unpause();

        sut.process(steps);
    }

    function testCanNotStealFunds_Process_Permit() public {
        uint256 amount = 1000e6;
        IERC20 token = usdc;

        EIP2098Permit memory signedPermit = env.dealAndPermit(token, trader, traderPK, amount, address(sut));

        steps.push(StepCall(Step.PullFundsWithPermit, abi.encode(token, signedPermit, amount, hacker)));

        vm.expectRevert("ERC20Permit: invalid signature");
        vm.prank(hacker);
        sut.process(steps);

        assertEqDecimal(token.balanceOf(hacker), 0, 6, "hacker balance");
    }

    function testCanNotStealFunds_TransferCallback_Permit() public {
        uint256 amount = 1000e6;
        IERC20 token = usdc;

        EIP2098Permit memory signedPermit = env.dealAndPermit(token, trader, traderPK, amount, address(sut));

        steps.push(StepCall(Step.PullFundsWithPermit, abi.encode(token, signedPermit, amount, hacker)));

        vm.expectRevert(StrategyBlocks.NotPositionNFT.selector);
        vm.prank(hacker);
        sut.onERC721Received({ operator: hacker, from: trader, tokenId: 666, data: abi.encode(steps) });

        assertEqDecimal(token.balanceOf(hacker), 0, 6, "hacker balance");
    }

    function testCanNotStealFunds_Permit2() public {
        uint256 amount = 1000e6;
        IERC20 token = usdc;

        EIP2098Permit memory signedPermit = env.dealAndPermit2(token, trader, traderPK, amount, address(sut));

        steps.push(StepCall(Step.PullFundsWithPermit2, abi.encode(token, signedPermit, amount, hacker)));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        vm.prank(hacker);
        sut.process(steps);

        assertEqDecimal(token.balanceOf(hacker), 0, 6, "hacker balance");
    }

    function testCanNotStealPosition_Permit2() public {
        TestInstrument memory ethUsdc = env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        (, PositionId existingPosition,) = env.positionActions().openPosition({
            symbol: ethUsdc.symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });

        PositionPermit memory positionPermit = env.positionIdPermit2(existingPosition, trader, traderPK, address(sut));

        steps.push(StepCall(Step.PullPosition, abi.encode(positionPermit)));

        vm.expectRevert(SignatureVerification.InvalidSigner.selector);
        vm.prank(hacker);
        sut.process(steps);

        assertEq(positionNFT.balanceOf(hacker), 0, "hacker balance");
    }

    function testFlashLoanCallbackIsProtected() public {
        vm.expectRevert(StrategyBlocks.InvalidCallback.selector);
        sut.continueActionProcessing(address(0), address(0), address(0), 0, 0, "hola");
    }

    function testRetrieveERC20() public {
        expectAccessControl(hacker, OPERATOR_ROLE);
        sut.retrieve(usdc, hacker);

        address someAddr = makeAddr("someAddr");
        deal(address(usdc), address(sut), 1000e6);

        vm.prank(operator);
        sut.retrieve(usdc, someAddr);

        assertEqDecimal(usdc.balanceOf(someAddr), 1000e6, 6, "someAddr balance");
    }

    function testRetrieveNative() public {
        expectAccessControl(hacker, OPERATOR_ROLE);
        sut.retrieveNative(payable(hacker));

        address payable someAddr = payable(makeAddr("someAddr"));
        vm.deal(address(sut), 10 ether);

        vm.prank(operator);
        sut.retrieveNative(someAddr);

        assertEqDecimal(address(someAddr).balance, 10 ether, 18, "someAddr balance");
    }

    function testRetrievePosition() public {
        (, PositionId positionId,) = env.positionActions().openPosition({
            symbol: env.createInstrument(env.erc20(WETH), env.erc20(USDC)).symbol,
            mm: MM_AAVE,
            quantity: 10 ether,
            cashflow: 4000e6,
            cashflowCcy: Currency.Quote
        });
        vm.prank(trader);
        positionNFT.transferFrom(trader, address(sut), positionId.asUint());

        expectAccessControl(hacker, OPERATOR_ROLE);
        sut.retrieve(positionId, hacker);

        address someAddr = makeAddr("someAddr");

        vm.prank(operator);
        sut.retrieve(positionId, someAddr);

        assertEq(positionNFT.positionOwner(positionId), someAddr, "position owner");
    }

    function testRetrieveFromVault() public {
        // This will implicitly enable the token on the vault
        env.createInstrument(env.erc20(WETH), env.erc20(USDC));

        expectAccessControl(hacker, OPERATOR_ROLE);
        sut.retrieveFromVault(usdc, hacker);

        address someAddr = makeAddr("someAddr");
        deal(address(usdc), address(vault), 1000e6);
        vm.prank(address(sut));
        vault.deposit(usdc, address(sut), 1000e6);

        vm.prank(operator);
        sut.retrieveFromVault(usdc, someAddr);

        assertEqDecimal(usdc.balanceOf(someAddr), 1000e6, 6, "someAddr balance");
    }

}

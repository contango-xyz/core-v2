//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../../Mock.sol";
import "../../TestSetup.t.sol";

contract EulerMoneyMarketTest is Test {

    using Address for *;
    using ERC20Lib for *;

    Env internal env;
    EulerMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;

    IEulerVault public constant ethVault = IEulerVault(0xD8b27CF359b7D15710a5BE299AF6e7Bf904984C2);
    IEulerVault public constant usdcVault = IEulerVault(0x797DD80692c3b2dAdabCe8e30C07fDE5307D48a9);
    IERC20 public constant rewardToken = IERC20(0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b);
    IEthereumVaultConnector public evc;
    IRewardStreams public rewards;
    EulerRewardsOperator public rewardOperator;
    address trader;
    uint16 ethId;
    uint16 usdcId;

    function setUp() public {
        env = provider(Network.Mainnet);
        env.init(20_678_328);

        contango = address(env.contango());

        sut = EulerMoneyMarket(address(env.positionFactory().moneyMarket(MM_EULER)));
        env.createInstrument(env.erc20(WETH), env.erc20(USDC));
        evc = sut.evc();
        rewards = sut.rewards();
        rewardOperator = sut.rewardOperator();

        trader = makeAddr("trader");

        uint128[] memory rewardAmounts = new uint128[](2);
        rewardAmounts[0] = 1000e18;
        rewardAmounts[1] = 1000e18;
        env.dealAndApprove(rewardToken, address(this), 2000e18, address(rewards));
        rewards.registerReward(ethVault, rewardToken, 0, rewardAmounts);

        vm.startPrank(TIMELOCK_ADDRESS);
        rewardOperator.addLiveReward(ethVault, rewardToken);

        ethId = sut.reverseLookup().setVault(ethVault);
        usdcId = sut.reverseLookup().setVault(usdcVault);
        vm.stopPrank();

        positionId = encode(Symbol.wrap("WETHUSDC"), MM_EULER, PERP, 0, baseQuotePayload(ethId, usdcId));

        vm.startPrank(contango);
        positionId = env.positionNFT().mint(positionId, trader);
        sut = EulerMoneyMarket(address(env.positionFactory().createUnderlyingPosition(positionId)));

        sut.initialise(positionId, env.token(WETH), env.token(USDC));
        vm.stopPrank();

        stubChainlinkPrice(1000e8, address(env.erc20(WETH).chainlinkUsdOracle));
        stubChainlinkPrice(1e8, address(env.erc20(USDC).chainlinkUsdOracle));
    }

    function testInitialise_InvalidExpiry() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployEulerMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EULER, PERP - 1, 1);

        vm.expectRevert(InvalidExpiry.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise_InvalidMoneyMarketId() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        sut = env.deployer().deployEulerMoneyMarket(env, IContango(contango));
        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP, 1);

        vm.expectRevert(IMoneyMarket.InvalidMoneyMarketId.selector);
        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);
    }

    function testInitialise() public {
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        vm.startPrank(contango);
        positionId = env.positionNFT().mint(encode(Symbol.wrap("WETHUSDC"), MM_EULER, PERP, 0, baseQuotePayload(ethId, usdcId)), trader);
        sut = EulerMoneyMarket(address(env.positionFactory().createUnderlyingPosition(positionId)));
        vm.stopPrank();

        vm.expectCall(
            address(evc), abi.encodeWithSelector(IEthereumVaultConnector.enableCollateral.selector, address(sut), address(ethVault))
        );
        vm.expectCall(
            address(evc), abi.encodeWithSelector(IEthereumVaultConnector.enableController.selector, address(sut), address(usdcVault))
        );

        vm.prank(contango);
        sut.initialise(positionId, lendToken, borrowToken);

        assertEq(lendToken.allowance(address(sut), address(ethVault)), type(uint256).max, "lendToken allowance");
        assertEq(borrowToken.allowance(address(sut), address(usdcVault)), type(uint256).max, "borrowToken allowance");
    }

    function testLifeCycle_HP() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(15 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");

        vm.prank(contango);
        sut.claimRewards(positionId, lendToken, borrowToken, address(this));
        assertEqDecimal(rewardToken.balanceOf(address(this)), 548.173776455026455026e18, 18, "rewards balance");
    }

    function testLifeCycle_RepayInExcess() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt * 2, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt * 2);

        assertEq(repaid, debt, "repaid all debt");
        assertEqDecimal(sut.debtBalance(positionId, borrowToken), 0, borrowToken.decimals(), "debt is zero");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral, address(this));

        assertEq(withdrew, collateral, "withdrew all collateral");
        assertEqDecimal(sut.collateralBalance(positionId, lendToken), 0, lendToken.decimals(), "collateral is zero");
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral, lendToken.decimals(), "withdrawn balance");
    }

    function testRepayEmptyPosition() public {
        IERC20 borrowToken = env.token(USDC);
        env.dealAndApprove(borrowToken, contango, 10e6, address(sut));
        vm.prank(contango);
        sut.repay(positionId, borrowToken, 10e6);
    }

    function testLifeCycle_PartialRepayWithdraw() public {
        // setup
        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        uint256 lendAmount = 10 ether;
        uint256 borrowAmount = 1000e6;

        // lend
        env.dealAndApprove(lendToken, contango, lendAmount, address(sut));
        vm.prank(contango);
        uint256 lent = sut.lend(positionId, lendToken, lendAmount);
        assertApproxEqAbsDecimal(lent, lendAmount, lendToken.decimals(), 1, "lent amount");

        // borrow
        vm.prank(contango);
        uint256 borrowed = sut.borrow(positionId, borrowToken, borrowAmount, address(this));
        assertEqDecimal(borrowed, borrowAmount, borrowToken.decimals(), "borrowed amount");
        assertEqDecimal(borrowToken.balanceOf(address(this)), borrowAmount, borrowToken.decimals(), "borrowed balance");

        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), lendAmount, 1, lendToken.decimals(), "collateralBalance after lend + borrow"
        );
        assertApproxEqAbsDecimal(
            sut.debtBalance(positionId, borrowToken), borrowAmount, 1, borrowToken.decimals(), "debtBalance after lend + borrow"
        );

        skip(10 days);

        // repay
        uint256 debt = sut.debtBalance(positionId, borrowToken);
        env.dealAndApprove(borrowToken, contango, debt / 4, address(sut));
        vm.prank(contango);
        uint256 repaid = sut.repay(positionId, borrowToken, debt / 4);

        assertEq(repaid, debt / 4, "repaid half debt");
        assertApproxEqAbsDecimal(sut.debtBalance(positionId, borrowToken), debt / 4 * 3, 5, borrowToken.decimals(), "debt is 3/4");

        // withdraw
        uint256 collateral = sut.collateralBalance(positionId, lendToken);
        vm.prank(contango);
        uint256 withdrew = sut.withdraw(positionId, lendToken, collateral / 4, address(this));

        assertEq(withdrew, collateral / 4, "withdrew half collateral");
        assertApproxEqAbsDecimal(
            sut.collateralBalance(positionId, lendToken), collateral / 4 * 3, 5, lendToken.decimals(), "collateral is 3/4"
        );
        assertEqDecimal(lendToken.balanceOf(address(this)), collateral / 4, lendToken.decimals(), "withdrawn balance");
    }

    function testIERC165() public view {
        assertTrue(sut.supportsInterface(type(IMoneyMarket).interfaceId), "IMoneyMarket");
        assertFalse(sut.supportsInterface(type(IFlashBorrowProvider).interfaceId), "IFlashBorrowProvider");
    }

}

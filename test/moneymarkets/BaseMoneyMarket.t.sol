//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

contract BaseMoneyMarketTest is Test {

    using ERC20Lib for *;

    Env internal env;
    BaseMoneyMarket internal sut;
    PositionId internal positionId;
    address internal contango;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();

        contango = address(env.contango());

        sut = new FooMoneyMarket(MoneyMarketId.wrap(0), env.contango());

        positionId = env.encoder().encodePositionId(Symbol.wrap("WETHUSDC"), MM_EXACTLY, PERP, 1);
    }

    function testMoneyMarketPermissions() public {
        address hacker = address(0x666);

        IERC20 lendToken = env.token(WETH);
        IERC20 borrowToken = env.token(USDC);

        // only contango
        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.initialise(positionId, lendToken, borrowToken);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.lend(positionId, lendToken, 0);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.withdraw(positionId, lendToken, 0, hacker);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.borrow(positionId, borrowToken, 0, hacker);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.repay(positionId, borrowToken, 0);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, hacker));
        sut.claimRewards(positionId, lendToken, borrowToken, hacker);
    }

}

contract FooMoneyMarket is BaseMoneyMarket {

    constructor(MoneyMarketId _moneyMarketId, IContango _contango) BaseMoneyMarket(_moneyMarketId, _contango) { }

    function NEEDS_ACCOUNT() external pure returns (bool) {
        return true;
    }

    function _initialise(PositionId positionId, IERC20 collateralAsset, IERC20 debtAsset) internal override { }

    function _lend(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        override
        returns (uint256 actualAmount)
    { }

    function _withdraw(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    { }

    function _borrow(PositionId positionId, IERC20 asset, uint256 amount, address to, uint256)
        internal
        override
        returns (uint256 actualAmount)
    { }

    function _repay(PositionId positionId, IERC20 asset, uint256 amount, address payer, uint256)
        internal
        override
        returns (uint256 actualAmount)
    { }

    function _collateralBalance(PositionId positionId, IERC20 asset) internal override returns (uint256 balance) { }

    function _debtBalance(PositionId positionId, IERC20 asset) internal override returns (uint256 balance) { }

}

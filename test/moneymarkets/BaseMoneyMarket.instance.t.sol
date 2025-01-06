//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../TestSetup.t.sol";

contract BaseMoneyMarketInstanceTest is Test {

    PositionId positionId;
    IContango contango;
    IERC20 usdc;
    PositionNFT nft;
    address owner;

    function setUp() public {
        vm.createSelectFork("mainnet", 20_336_106);
        positionId = PositionId.wrap(0x657a45544857455448000000000000000effffffff0000000002000000000268);
        contango = IContango(0x6Cae28b3D09D8f8Fc74ccD496AC986FC84C0C24E);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        nft = contango.positionNFT();
        owner = 0xfc2af546358825b94A40aF442ac08F27facF0859;

        vm.startPrank(TIMELOCK_ADDRESS);
        CometMoneyMarket mm = new CometMoneyMarket({
            _moneyMarketId: MM_COMET,
            _contango: contango,
            _reverseLookup: CometReverseLookup(0x94e46A68814D09a3131221eec190512a374e6BF1),
            _rewards: ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40)
        });

        IMoneyMarket existentMoneyMarket = contango.positionFactory().moneyMarket(MM_COMET);
        UpgradeableBeacon beacon = ImmutableBeaconProxy(payable(address(existentMoneyMarket))).__beacon();
        beacon.upgradeTo(address(mm));

        vm.stopPrank();
    }

    function testRetrieve_ERC20Funds() public {
        IMoneyMarket impl = contango.positionFactory().moneyMarket(positionId);

        deal(address(usdc), address(impl), 100e6);

        uint256 balanceBefore = usdc.balanceOf(owner);

        impl.retrieve(positionId, usdc);

        assertEqDecimal(usdc.balanceOf(owner), balanceBefore + 100e6, 6, "Retrieved balance");
    }

    function testRetrieve_ClosedPosition() public {
        positionId = PositionId.wrap(0x574254435553444300000000000000000effffffff0000000001000000000179);
        owner = 0xA8DDc541d443d29D61375A3E4E190Ac81fB88608;

        IMoneyMarket impl = contango.positionFactory().moneyMarket(positionId);

        deal(address(usdc), address(impl), 100e6);

        uint256 balanceBefore = usdc.balanceOf(owner);

        impl.retrieve(positionId, usdc);

        assertEqDecimal(usdc.balanceOf(owner), balanceBefore + 100e6, 6, "Retrieved balance");
    }

    function testRetrieve_NativeFunds() public {
        IMoneyMarket impl = contango.positionFactory().moneyMarket(positionId);

        vm.deal(address(impl), 1 ether);

        uint256 balanceBefore = owner.balance;

        impl.retrieve(positionId, IERC20(address(0)));

        assertEqDecimal(owner.balance, balanceBefore + 1 ether, 18, "Retrieved balance");
    }

    function testRetrieve_InvalidPositionId() public {
        IMoneyMarket impl = contango.positionFactory().moneyMarket(positionId);
        positionId = PositionId.wrap(0x5745544855534443000000000000000001ffffffff000000000000000000015d);

        vm.expectRevert(abi.encodeWithSelector(IMoneyMarket.InvalidPositionId.selector, positionId));
        impl.retrieve(positionId, IERC20(address(0)));
    }

    function testRetrieve_TokenCantBeRetrieved() public {
        IMoneyMarket impl = contango.positionFactory().moneyMarket(positionId);

        IERC20 aUSDC = IERC20(0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c);

        vm.expectRevert(abi.encodeWithSelector(IMoneyMarket.TokenCantBeRetrieved.selector, aUSDC));
        impl.retrieve(positionId, aUSDC);
    }

}

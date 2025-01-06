//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../BaseTest.sol";

contract Upgrades is BaseTest, IContangoEvents, IContangoErrors {

    Env internal env;
    address newImpl;

    function setUp() public {
        env = provider(Network.Optimism);
        env.init();
        newImpl = address(new NewImpl());
    }

    function testUpgradeContango() public {
        _testUpgrade(address(env.contango()), abi.encodeWithSelector(Contango.initialize.selector, TIMELOCK));
    }

    function testUpgradeVault() public {
        _testUpgrade(address(env.vault()), abi.encodeWithSelector(Vault.initialize.selector, TIMELOCK));
    }

    function testUpgradeContangoLens() public {
        _testUpgrade(address(env.contangoLens()), abi.encodeWithSelector(ContangoLens.initialize.selector, TIMELOCK));
    }

    function testUpgradeOrderManager() public {
        _testUpgrade(address(env.orderManager()), abi.encodeWithSelector(OrderManager.initialize.selector, TIMELOCK, 1e4, 1, address(0)));
    }

    function testUpgradeStrategyBuilder() public {
        _testUpgrade(address(env.strategyBuilder()), abi.encodeWithSelector(StrategyBlocks.initialize.selector, TIMELOCK));
    }

    function testUpgradeMaestro() public {
        address impl = address(env.maestro());

        UUPSUpgradeable proxy = UUPSUpgradeable(address(new ERC1967Proxy(impl, "")));

        vm.expectRevert(abi.encodeWithSelector(Unauthorised.selector, address(this)));
        proxy.upgradeTo(impl);

        vm.prank(TIMELOCK_ADDRESS);
        proxy.upgradeTo(newImpl);
    }

    function _testUpgrade(address impl, bytes memory init) public {
        UUPSUpgradeable proxy = UUPSUpgradeable(address(new ERC1967Proxy(impl, init)));

        expectAccessControl(address(this), "");
        proxy.upgradeTo(impl);

        vm.prank(TIMELOCK_ADDRESS);
        proxy.upgradeTo(newImpl);
    }

}

contract NewImpl is UUPSUpgradeable {

    function _authorizeUpgrade(address) internal view override { }

}

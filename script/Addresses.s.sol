// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "forge-std/Vm.sol";
import "forge-std/StdJson.sol";

import "test/Network.sol";

import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract Addresses {

    using stdJson for string;

    Vm private vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function _loadAddress(string memory key) internal view returns (address a) {
        a = _loadAddressMaybe(key);
        require(a != address(0), string.concat("InitialDeployment: got address(0) for ", key));
    }

    function _loadAddressMaybe(string memory key) internal view returns (address a) {
        try vm.parseJsonAddress(_networksJson(), string.concat("$.", currentNetwork().toString(), ".", key, ".address")) returns (
            address addr
        ) {
            a = addr;
        } catch {
            a = address(0);
        }
    }

    function _loadToken(string memory key) internal view returns (IERC20 t) {
        t = IERC20(_loadAddress(key));
    }

    function _networksJson() internal view returns (string memory json) {
        json = vm.readFile(string.concat(vm.projectRoot(), "/networks.json"));
    }

    function _updateJson(string memory key, address addr) internal {
        string memory network = currentNetwork().toString();
        string memory file = string.concat(vm.projectRoot(), "/networks.json");
        vm.writeJson(vm.toString(addr), file, string.concat("$.", network, ".", key, ".address"));

        // TODO this is wrong for Arbitrum as it returns the L1 block number, but Foundry atm has no Arbitrum pre-compiles support
        uint256 blockNumber = currentNetwork() == Network.LocalhostArbitrum ? 273_737_324 : block.number;

        vm.writeJson(vm.toString(blockNumber), file, string.concat("$.", network, ".", key, ".startBlock"));

        require(
            _networksJson().readAddress(string.concat("$.", network, ".", key, ".address")) == addr,
            string.concat("InitialDeployment: failed to update networks.json for ", key)
        );
    }

}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library LibAddressSet {

    function add(AddressSet storage s, address addr) internal returns (address) {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
        return addr;
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    function rand(AddressSet storage s, uint256 seed) internal returns (address) {
        if (s.addrs.length > 0) return s.addrs[seed % s.addrs.length];
        else return add(s, address(0xb0b));
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func)
        internal
        returns (uint256)
    {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }

}

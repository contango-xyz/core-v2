// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "./TestSetup.t.sol";

contract StrictMock {

    string public name;

    function setName(string memory _name) public {
        name = _name;
        VM.label(address(this), name);
    }

    error NotMocked(string name, address mock, bytes4 sig, bytes data);

    fallback() external payable {
        revert NotMocked(name, address(this), msg.sig, msg.data);
    }

    receive() external payable {
        revert NotMocked(name, address(this), msg.sig, "");
    }

}

contract LenientMock {

    fallback() external payable { }

}

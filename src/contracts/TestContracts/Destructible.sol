// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

contract Destructible {
    receive() external payable {}

    function destruct(address payable _receiver) external {
        selfdestruct(_receiver);
    }
}

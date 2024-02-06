// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

contract CheckContract {
    function checkContract(address _account) internal view {
        require(_account != address(0), "Account cannot be zero address");
        require(_account.code.length > 0, "Account code size cannot be zero");
    }
}

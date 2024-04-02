// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface ITellorCaller {
    function getTellorCurrentValue(bytes32 _queryId) external returns (bool, uint256, uint256);
}

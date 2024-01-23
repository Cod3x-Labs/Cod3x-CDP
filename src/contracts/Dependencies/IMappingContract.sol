// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface IMappingContract {
    function getTellorID(bytes32 _id) external view returns (bytes32);
}

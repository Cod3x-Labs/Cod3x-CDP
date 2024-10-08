// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IStabilityPool} from "./IStabilityPool.sol";

interface ILiquidationHelper {
    function liquidate(address _borrower, address _collateral, address _caller) external;
    function liquidateTroves(address _collateral, uint _n, address _caller) external;
    function batchLiquidateTroves(
        address _collateral,
        address[] memory _troveArray,
        address _caller
    ) external;
}

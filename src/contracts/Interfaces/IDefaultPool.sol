// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IPool} from "./IPool.sol";

interface IDefaultPool is IPool {
    // --- Events ---
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event DefaultPoolLUSDDebtUpdated(address _collateral, uint _LUSDDebt);
    event DefaultPoolCollateralBalanceUpdated(address _collateral, uint _amount);

    // --- Functions ---
    function sendCollateralToActivePool(address _collateral, uint _amount) external;
    function pullCollateralFromActivePool(address _collateral, uint _amount) external;
}

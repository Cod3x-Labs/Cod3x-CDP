// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IPool} from "./IPool.sol";

interface IActivePool is IPool {
    // --- Events ---
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event ActivePoolLUSDDebtUpdated(address _collateral, uint _LUSDDebt);
    event ActivePoolCollateralBalanceUpdated(address _collateral, uint _amount);
    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);
    event RedemptionHelperAddressChanged(address _redemptionHelperAddress);
    event LiquidationHelperAddressChanged(address _liquidationHelperAddress);

    // --- Functions ---
    function sendCollateral(address _collateral, address _account, uint _amount) external;

    function pullCollateralFromBorrowerOperationsOrDefaultPool(
        address _collateral,
        uint _amount
    ) external;
}

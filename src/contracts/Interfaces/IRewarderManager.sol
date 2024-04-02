// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface IRewarderManager {
    function onDebtIncrease(address _borrower, address _collateral, uint _amount) external;
    function onDebtDecrease(address _borrower, address _collateral, uint _amount) external;
    function onCollIncrease(address _borrower, address _collateral, uint _amount) external;
    function onCollDecrease(address _borrower, address _collateral, uint _amount) external;
    function onTroveClose(address _borrower, address _collateral, uint _closedStatus) external;
}

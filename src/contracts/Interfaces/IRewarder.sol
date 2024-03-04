// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface IRewarder {
    function onDebtIncrease(address _borrower, uint _amount) external;
    function onDebtDecrease(address _borrower, uint _amount) external;
    function onCollIncrease(address _borrower, uint _amount) external;
    function onCollDecrease(address _borrower, uint _amount) external;
    function onTroveClose(address _borrower, uint _closedStatus) external;
}

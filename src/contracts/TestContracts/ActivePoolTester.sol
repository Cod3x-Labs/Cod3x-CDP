// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../ActivePool.sol";

contract ActivePoolTester is ActivePool {
    using SafeERC20 for IERC20;

    function unprotectedIncreaseLUSDDebt(address _collateral, uint _amount) external {
        LUSDDebt[_collateral] = LUSDDebt[_collateral] + _amount;
    }

    function unprotectedPullCollateral(address _collateral, uint _amount) external {
        collAmount[_collateral] = collAmount[_collateral] + _amount;
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);
    }
}

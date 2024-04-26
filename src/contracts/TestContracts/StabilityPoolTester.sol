// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {StabilityPool, SafeERC20, IERC20} from "../StabilityPool.sol";

contract StabilityPoolTester is StabilityPool {
    using SafeERC20 for IERC20;

    function unprotectedPullCollateral(address _collateral, uint _amount) external {
        collAmounts[_collateral] = collAmounts[_collateral] + _amount;
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function setCurrentScale(uint128 _currentScale) external {
        currentScale = _currentScale;
    }

    function setTotalDeposits(uint _totalLUSDDeposits) external {
        totalLUSDDeposits = _totalLUSDDeposits;
    }
}

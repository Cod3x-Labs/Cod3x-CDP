// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// We must use non-ERC4626 withdraw function because the 4626 version can fail
interface IReaperVault is IERC4626 {
    /**
     * @notice Function to exit the system. The vault will withdraw the required tokens
     * from the strategies and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     * @param _shares the number of shares to burn
     */
    function withdraw(uint256 _shares) external;
}

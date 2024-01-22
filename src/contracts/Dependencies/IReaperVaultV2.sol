// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import "./IERC20.sol";

interface IReaperVaultV2 is IERC20 {
    function balance() external view returns (uint256);

    function deposit(uint256 _amount) external;

    function token() external view returns (address);

    function withdraw(uint256 _shares) external;
}

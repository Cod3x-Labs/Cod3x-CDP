// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {CheckContract} from "../Dependencies/CheckContract.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TokenScript is CheckContract {
    using SafeERC20 for IERC20;

    string public constant NAME = "TokenScript";

    IERC20 immutable token;

    constructor(address _tokenAddress) {
        checkContract(_tokenAddress);
        token = IERC20(_tokenAddress);
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return token.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return token.approve(spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return token.transferFrom(sender, recipient, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue) external {
        return token.safeIncreaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external {
        return token.safeDecreaseAllowance(spender, subtractedValue);
    }
}

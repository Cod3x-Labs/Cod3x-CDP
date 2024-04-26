// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IPriceFeed} from "./IPriceFeed.sol";

interface ILiquityBase {
    function priceFeed() external view returns (IPriceFeed);
}

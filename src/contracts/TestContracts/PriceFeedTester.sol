// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {PriceFeed} from "../PriceFeed.sol";

contract PriceFeedTester is PriceFeed {
    function setLastGoodPrice(address _collateral, uint _lastGoodPrice) external {
        lastGoodPrice[_collateral] = _lastGoodPrice;
    }

    function setStatus(address _collateral, Status _status) external {
        status[_collateral] = _status;
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

import {ITellorCaller} from "../Interfaces/ITellorCaller.sol";
import {UsingTellor} from "./UsingTellor.sol";

/*
 * This contract has a single external function that calls Tellor: getTellorCurrentValue().
 *
 * The function is called by the Liquity contract PriceFeed.sol. If any of its inner calls to Tellor revert,
 * this function will revert, and PriceFeed will catch the failure and handle it accordingly.
 *
 * The function comes from Tellor's own wrapper contract, 'UsingTellor.sol':
 * https://github.com/tellor-io/usingtellor/blob/master/contracts/UsingTellor.sol
 *
 */
contract TellorCaller is UsingTellor, ITellorCaller {
    mapping(bytes32 => uint256) public lastStoredTimestamps;
    mapping(bytes32 => uint256) public lastStoredPrices;

    constructor(address payable _tellorMasterAddress) UsingTellor(_tellorMasterAddress) {}

    /*
     * getTellorCurrentValue(): identical to getCurrentValue() in UsingTellor.sol
     *
     * @dev Allows the user to get the latest value for the queryId specified
     * @param _queryId is the queryId to look up the value for
     * @return ifRetrieve bool true if it is able to retrieve a value, the value, and the value's timestamp
     * @return value the value retrieved
     * @return _timestampRetrieved the value's timestamp
     */
    function getTellorCurrentValue(
        bytes32 _queryId
    ) external override returns (bool ifRetrieve, uint256 value, uint256 _timestampRetrieved) {
        (bytes memory data, uint256 timestamp) = getDataBefore(
            _queryId,
            block.timestamp - 20 minutes
        );
        uint256 _value = abi.decode(data, (uint256));
        if (timestamp == 0 || _value == 0) return (false, _value, timestamp);
        if (timestamp > lastStoredTimestamps[_queryId]) {
            lastStoredTimestamps[_queryId] = timestamp;
            lastStoredPrices[_queryId] = _value;
            return (true, _value, timestamp);
        } else {
            return (true, lastStoredPrices[_queryId], lastStoredTimestamps[_queryId]);
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface IPriceFeed {
    // --- Events ---
    event LastGoodPriceUpdated(address _collateral, uint _lastGoodPrice);

    // --- Function ---
    function fetchPrice(address _collateral) external returns (uint);
    function updateChainlinkAggregator(
        address _collateral,
        address _priceAggregatorAddress
    ) external;
    function updateTellorQueryID(address _collateral, bytes32 _queryId) external;
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

interface ICommunityIssuance {
    // --- Events ---

    event OATHTokenAddressSet(address _lqtyTokenAddress);
    event StabilityPoolAddressSet(address _stabilityPoolAddress);
    event TotalOathIssuedUpdated(uint _totalLQTYIssued);
    event OathTokenAddressSet(address _oathTokenAddress);
    event LogRewardPerSecond(uint256 _rewardPerSecond);
    event TotalOATHIssuedUpdated(address indexed _oathTokenAddress, uint256 _totalOATHIssued);

    // --- Functions ---

    function setAddresses(address _lqtyTokenAddress, address _stabilityPoolAddress) external;

    function issueOath() external returns (uint);

    function sendOath(address _account, uint _LQTYamount) external;
}

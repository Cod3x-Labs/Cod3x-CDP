// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../LQTY/CommunityIssuance.sol";

contract CommunityIssuanceTester is CommunityIssuance {
    using SafeMath for uint;

    function unprotectedIssueLQTY() external returns (uint issuance) {
        if (lastIssuanceTimestamp < lastDistributionTime) {
            uint256 endTimestamp = block.timestamp > lastDistributionTime
                ? lastDistributionTime
                : block.timestamp;
            uint256 timePassed = endTimestamp.sub(lastIssuanceTimestamp);
            issuance = getRewardAmount(timePassed);
            totalOATHIssued[oathToken] = totalOATHIssued[oathToken].add(issuance);
        }

        lastIssuanceTimestamp = block.timestamp;
    }
}

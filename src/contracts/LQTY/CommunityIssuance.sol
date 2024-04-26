// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICommunityIssuance} from "../Interfaces/ICommunityIssuance.sol";
import {BaseMath} from "../Dependencies/BaseMath.sol";
import {LiquityMath} from "../Dependencies/LiquityMath.sol";
import {Ownable} from "../Dependencies/Ownable.sol";
import {CheckContract} from "../Dependencies/CheckContract.sol";

contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    using SafeERC20 for IERC20;

    // --- Data ---

    string public constant NAME = "CommunityIssuance";

    bool public initialized = false;

    IERC20 public oathToken;

    address public stabilityPoolAddress;

    mapping(IERC20 => uint256) public totalOATHIssued;
    uint256 public lastDistributionTime;
    uint256 public distributionPeriod;
    uint256 internal _rewardPerSecond;
    uint256 public lastIssuanceTimestamp;

    // --- Functions ---

    constructor() {
        distributionPeriod = 14 days;
    }

    function setAddresses(
        address _oathTokenAddress,
        address _stabilityPoolAddress
    ) external override onlyOwner {
        require(!initialized, "issuance has been initialized");
        checkContract(_oathTokenAddress);
        checkContract(_stabilityPoolAddress);

        oathToken = IERC20(_oathTokenAddress);
        stabilityPoolAddress = _stabilityPoolAddress;

        initialized = true;

        emit OathTokenAddressSet(_oathTokenAddress);
        emit StabilityPoolAddressSet(_stabilityPoolAddress);
    }

    function setOathToken(address _oathTokenAddress) external onlyOwner {
        require(
            lastIssuanceTimestamp >= lastDistributionTime,
            "last distribution has not been fully issued"
        );
        checkContract(_oathTokenAddress);
        oathToken = IERC20(_oathTokenAddress);
        emit OathTokenAddressSet(_oathTokenAddress);
    }

    // @dev issues a set amount of Oath to the stability pool
    function issueOath() external override returns (uint256 issuance) {
        _requireCallerIsStabilityPool();

        uint256 _lastIssuanceTimestamp = lastIssuanceTimestamp;
        uint256 _lastDistributionTime = lastDistributionTime;
        IERC20 _oathToken = oathToken;
        uint256 _totalOATHIssued = totalOATHIssued[_oathToken];
        if (_lastIssuanceTimestamp < _lastDistributionTime) {
            uint256 endTimestamp = block.timestamp > _lastDistributionTime
                ? _lastDistributionTime
                : block.timestamp;
            uint256 timePassed = endTimestamp - _lastIssuanceTimestamp;
            issuance = getRewardAmount(timePassed);

            _totalOATHIssued = _totalOATHIssued + issuance;
            totalOATHIssued[_oathToken] = _totalOATHIssued;
            emit TotalOATHIssuedUpdated(address(_oathToken), _totalOATHIssued);
        }

        lastIssuanceTimestamp = block.timestamp;
    }

    /*
      @dev funds the contract and updates the distribution
      @param amount: amount of $OATH to send to the contract
    */
    function fund(uint256 amount) external onlyOwner {
        require(amount != 0, "cannot fund 0");

        // roll any unissued OATH into new distribution
        uint256 _lastIssuanceTimestamp = lastIssuanceTimestamp;
        uint256 _lastDistributionTime = lastDistributionTime;
        uint256 _amount = amount;
        if (_lastIssuanceTimestamp < _lastDistributionTime) {
            uint256 timeLeft = _lastDistributionTime - _lastIssuanceTimestamp;
            uint256 notIssued = getRewardAmount(timeLeft);
            amount = amount + notIssued;
        }

        uint256 _distributionPeriod = distributionPeriod;
        _rewardPerSecond = (amount * DECIMAL_PRECISION) / _distributionPeriod;
        lastDistributionTime = block.timestamp + _distributionPeriod;
        lastIssuanceTimestamp = block.timestamp;

        oathToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit LogRewardPerSecond(rewardPerSecond());
    }

    // Owner-only function to update the distribution period
    function updateDistributionPeriod(uint256 _newDistributionPeriod) external onlyOwner {
        distributionPeriod = _newDistributionPeriod;
    }

    function sendOath(address _account, uint256 _OathAmount) external override {
        _requireCallerIsStabilityPool();

        oathToken.safeTransfer(_account, _OathAmount);
    }

    function rewardPerSecond() public view returns (uint) {
        return _rewardPerSecond / DECIMAL_PRECISION;
    }

    function getRewardAmount(uint seconds_) public view returns (uint) {
        return (_rewardPerSecond * seconds_) / DECIMAL_PRECISION;
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "CommunityIssuance: caller is not SP");
    }
}

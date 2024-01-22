// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import "../Dependencies/SafeERC20.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/LiquityMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";


contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    // --- Data ---

    string constant public NAME = "CommunityIssuance";

    bool public initialized = false;

    IERC20 public oathToken;

    address public stabilityPoolAddress;

    mapping(IERC20 => uint256) public totalOATHIssued;
    uint256 public lastDistributionTime;
    uint256 public distributionPeriod;
    uint256 internal _rewardPerSecond;

    uint256 public lastIssuanceTimestamp;

    // --- Events ---

    event OathTokenAddressSet(address _oathTokenAddress);
    event LogRewardPerSecond(uint256 _rewardPerSecond);
    event StabilityPoolAddressSet(address _stabilityPoolAddress);
    event TotalOATHIssuedUpdated(IERC20 indexed _oathTokenAddress, uint256 _totalOATHIssued);

    // --- Functions ---

    constructor() public {
        distributionPeriod = 14 days;
    }

    function setAddresses
    (
        address _oathTokenAddress, 
        address _stabilityPoolAddress
    ) 
        external 
        onlyOwner 
        override 
    {
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
        require(lastIssuanceTimestamp >= lastDistributionTime, "last distribution has not been fully issued");
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
            uint256 endTimestamp = block.timestamp > _lastDistributionTime ? _lastDistributionTime : block.timestamp;
            uint256 timePassed = endTimestamp.sub(_lastIssuanceTimestamp);
            issuance = getRewardAmount(timePassed);

            _totalOATHIssued = _totalOATHIssued.add(issuance);
            totalOATHIssued[_oathToken] = _totalOATHIssued;
            emit TotalOATHIssuedUpdated(_oathToken, _totalOATHIssued);
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
            uint256 timeLeft = _lastDistributionTime.sub(_lastIssuanceTimestamp);
            uint256 notIssued = getRewardAmount(timeLeft);
            amount = amount.add(notIssued);
        }

        uint256 _distributionPeriod = distributionPeriod;
        _rewardPerSecond = amount.mul(DECIMAL_PRECISION).div(_distributionPeriod);
        lastDistributionTime = block.timestamp.add(_distributionPeriod);
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
        return _rewardPerSecond.div(DECIMAL_PRECISION);
    }

    function getRewardAmount(uint seconds_) public view returns (uint) {
        return _rewardPerSecond.mul(seconds_).div(DECIMAL_PRECISION);
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(msg.sender == stabilityPoolAddress, "CommunityIssuance: caller is not SP");
    }
}

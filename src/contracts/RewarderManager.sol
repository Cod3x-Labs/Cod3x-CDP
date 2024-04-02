// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "./Interfaces/IRewarder.sol";
import "./Interfaces/IRewarderManager.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/EnumerableSet.sol";
import "./Dependencies/Ownable.sol";

contract RewarderManager is Ownable, CheckContract, IRewarderManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    bool public initialized = false;
    mapping(address => EnumerableSet.AddressSet) private childrenRewarders;
    address public troveManagerAddress;

    event ChildAdded(address indexed _collateral, address indexed _child);
    event ChildRemoved(address indexed _collateral, address indexed _child);
    event TroveManagerAddressChanged(address _troveManagerAddress);

    function setAddresses(address _troveManagerAddress) external onlyOwner {
        require(!initialized, "Can only initialize once");
        checkContract(_troveManagerAddress);
        troveManagerAddress = _troveManagerAddress;
        emit TroveManagerAddressChanged(_troveManagerAddress);
        initialized = true;
    }

    /// @notice Adds a child rewarder to the childrenRewarders set.
    /// @param _childRewarder Address of the child rewarder contract to add.
    function addChild(address _collateral, address _childRewarder) external onlyOwner {
        checkContract(_childRewarder);
        require(childrenRewarders[_collateral].add(_childRewarder), "Address already in set");
        emit ChildAdded(_collateral, _childRewarder);
    }

    /// @notice Removes a child rewarder from the childrenRewarders set.
    /// @param _childRewarder Address of the child rewarder contract to remove.
    function removeChild(address _collateral, address _childRewarder) external onlyOwner {
        require(childrenRewarders[_collateral].remove(_childRewarder), "Address not in set");
        emit ChildRemoved(_collateral, _childRewarder);
    }

    /// @notice Returns the length of the childrenRewarders set.
    function getChildrenRewardersLength(address _collateral) public view returns (uint) {
        return childrenRewarders[_collateral].length();
    }

    /// @notice Returns the address for the child rewarder at a given index.
    /// NOTE: The EnumerableSet is not sorted in any particular order, even order of addition to the set.
    function getChildRewarderAt(address _collateral, uint _index) public view returns (address) {
        return childrenRewarders[_collateral].at(_index);
    }

    // --- Hooks ---

    function onDebtIncrease(address _borrower, address _collateral, uint _amount) external override {
        _requireCallerIsTroveManager();
        uint length = getChildrenRewardersLength(_collateral);
        for (uint i; i < length; ++i) {
            IRewarder(getChildRewarderAt(_collateral, i)).onDebtIncrease(_borrower, _amount);
        }
    }

    function onDebtDecrease(address _borrower, address _collateral, uint _amount) external override {
        _requireCallerIsTroveManager();
        uint length = getChildrenRewardersLength(_collateral);
        for (uint i; i < length; ++i) {
            IRewarder(getChildRewarderAt(_collateral, i)).onDebtDecrease(_borrower, _amount);
        }
    }

    function onCollIncrease(address _borrower, address _collateral, uint _amount) external override {
        _requireCallerIsTroveManager();
        uint length = getChildrenRewardersLength(_collateral);
        for (uint i; i < length; ++i) {
            IRewarder(getChildRewarderAt(_collateral, i)).onCollIncrease(_borrower, _amount);
        }
    }

    function onCollDecrease(address _borrower, address _collateral, uint _amount) external override {
        _requireCallerIsTroveManager();
        uint length = getChildrenRewardersLength(_collateral);
        for (uint i; i < length; ++i) {
            IRewarder(getChildRewarderAt(_collateral, i)).onCollDecrease(_borrower, _amount);
        }
    }

    function onTroveClose(
        address _borrower,
        address _collateral,
        uint _closedStatus
    ) external override {
        _requireCallerIsTroveManager();
        uint length = getChildrenRewardersLength(_collateral);
        for (uint i; i < length; ++i) {
            IRewarder(getChildRewarderAt(_collateral, i)).onTroveClose(_borrower, _closedStatus);
        }
    }

    // --- 'Require' wrapper functions ---

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "RewarderManager: Caller is not Trove Manager");
    }
}

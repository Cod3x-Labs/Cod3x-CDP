// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IActivePool} from "./Interfaces/IActivePool.sol";
import {ICollateralConfig} from "./Interfaces/ICollateralConfig.sol";
import {IDefaultPool} from "./Interfaces/IDefaultPool.sol";
import {Ownable} from "./Dependencies/Ownable.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
 * The Default Pool holds the collateral and LUSD debt for each collateral (but not LUSD tokens) from liquidations that have been redistributed
 * to active troves but not yet "applied", i.e. not yet recorded on a recipient active trove's struct.
 *
 * When a trove makes an operation that applies its pending collateral and LUSD debt, its pending collateral and LUSD debt is moved
 * from the Default Pool to the Active Pool.
 */
contract DefaultPool is Ownable, CheckContract, IDefaultPool {
    using SafeERC20 for IERC20;

    string public constant NAME = "DefaultPool";

    address public collateralConfigAddress;
    address public troveManagerAddress;
    address public activePoolAddress;
    mapping(address => uint256) internal collAmount; // collateral => amount tracker
    mapping(address => uint256) internal LUSDDebt; // collateral => corresponding debt tracker

    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);

    // --- Dependency setters ---

    function setAddresses(
        address _collateralConfigAddress,
        address _troveManagerAddress,
        address _activePoolAddress
    ) external onlyOwner {
        checkContract(_collateralConfigAddress);
        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);

        collateralConfigAddress = _collateralConfigAddress;
        troveManagerAddress = _troveManagerAddress;
        activePoolAddress = _activePoolAddress;

        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);

        renounceOwnership();
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the collAmount state variable.
     *
     * Not necessarily equal to the the contract's raw collateral balance - collateral can be forcibly sent to contracts.
     */
    function getCollateral(address _collateral) external view override returns (uint) {
        _requireValidCollateralAddress(_collateral);
        return collAmount[_collateral];
    }

    function getLUSDDebt(address _collateral) external view override returns (uint) {
        _requireValidCollateralAddress(_collateral);
        return LUSDDebt[_collateral];
    }

    // --- Pool functionality ---

    function sendCollateralToActivePool(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsTroveManager();
        address activePool = activePoolAddress; // cache to save an SLOAD
        collAmount[_collateral] = collAmount[_collateral] - _amount;
        emit DefaultPoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);
        emit CollateralSent(_collateral, activePool, _amount);

        IERC20(_collateral).safeIncreaseAllowance(activePool, _amount);
        IActivePool(activePoolAddress).pullCollateralFromBorrowerOperationsOrDefaultPool(
            _collateral,
            _amount
        );
    }

    function increaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsTroveManager();
        LUSDDebt[_collateral] = LUSDDebt[_collateral] + _amount;
        emit DefaultPoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function decreaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsTroveManager();
        LUSDDebt[_collateral] = LUSDDebt[_collateral] - _amount;
        emit DefaultPoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function pullCollateralFromActivePool(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsActivePool();
        collAmount[_collateral] = collAmount[_collateral] + _amount;
        emit DefaultPoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);

        IERC20(_collateral).safeTransferFrom(activePoolAddress, address(this), _amount);
    }

    // --- 'require' functions ---

    function _requireValidCollateralAddress(address _collateral) internal view {
        require(
            ICollateralConfig(collateralConfigAddress).isCollateralAllowed(_collateral),
            "Invalid collateral address"
        );
    }

    function _requireCallerIsActivePool() internal view {
        require(msg.sender == activePoolAddress, "DefaultPool: Caller is not the ActivePool");
    }

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == troveManagerAddress, "DefaultPool: Caller is not the TroveManager");
    }
}

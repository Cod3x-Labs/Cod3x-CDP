// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IActivePool} from "./Interfaces/IActivePool.sol";
import {ICollateralConfig} from "./Interfaces/ICollateralConfig.sol";
import {IDefaultPool} from "./Interfaces/IDefaultPool.sol";
import {ICollSurplusPool} from "./Interfaces/ICollSurplusPool.sol";
import {ITroveManager} from "./Interfaces/ITroveManager.sol";
import {Ownable} from "./Dependencies/Ownable.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*
 * The Active Pool holds the collateral and LUSD debt for each collateral (but not LUSD tokens) for all active troves.
 *
 * When a trove is liquidated, it's collateral and LUSD debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool {
    using SafeERC20 for IERC20;

    string public constant NAME = "ActivePool";

    bool public addressesSet = false;
    address public collateralConfigAddress;
    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public redemptionHelperAddress;
    address public liquidationHelperAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;
    address public collSurplusPoolAddress;
    mapping(address => uint256) internal collAmount; // collateral => amount tracker
    mapping(address => uint256) internal LUSDDebt; // collateral => corresponding debt tracker

    // --- Contract setters ---
    function setAddresses(
        address _collateralConfigAddress,
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _redemptionHelperAddress,
        address _liquidationHelperAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress
    ) external onlyOwner {
        require(!addressesSet, "Can call setAddresses only once");

        checkContract(_collateralConfigAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_redemptionHelperAddress);
        checkContract(_liquidationHelperAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collSurplusPoolAddress);

        collateralConfigAddress = _collateralConfigAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        redemptionHelperAddress = _redemptionHelperAddress;
        liquidationHelperAddress = _liquidationHelperAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;
        collSurplusPoolAddress = _collSurplusPoolAddress;

        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit RedemptionHelperAddressChanged(_redemptionHelperAddress);
        emit LiquidationHelperAddressChanged(_liquidationHelperAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);

        addressesSet = true;
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
     * Returns the collAmount state variable.
     *
     *Not necessarily equal to the the contract's raw collateral balance - collateral can be forcibly sent to contracts.
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

    function sendCollateral(address _collateral, address _account, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBOorTroveMorSPorLH();
        collAmount[_collateral] = collAmount[_collateral] - _amount;
        emit ActivePoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);
        emit CollateralSent(_collateral, _account, _amount);

        if (_account == defaultPoolAddress) {
            IERC20(_collateral).safeIncreaseAllowance(defaultPoolAddress, _amount);
            IDefaultPool(defaultPoolAddress).pullCollateralFromActivePool(_collateral, _amount);
        } else if (_account == collSurplusPoolAddress) {
            IERC20(_collateral).safeIncreaseAllowance(collSurplusPoolAddress, _amount);
            ICollSurplusPool(collSurplusPoolAddress).pullCollateralFromActivePool(
                _collateral,
                _amount
            );
        } else {
            IERC20(_collateral).safeTransfer(_account, _amount);
        }
    }

    function increaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBOorTroveM();
        LUSDDebt[_collateral] = LUSDDebt[_collateral] + _amount;
        emit ActivePoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function decreaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBOorTroveMorSPorRH();
        LUSDDebt[_collateral] = LUSDDebt[_collateral] - _amount;
        emit ActivePoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function pullCollateralFromBorrowerOperationsOrDefaultPool(
        address _collateral,
        uint _amount
    ) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        collAmount[_collateral] = collAmount[_collateral] + _amount;
        emit ActivePoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);

        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);
    }

    // --- 'require' functions ---

    function _requireValidCollateralAddress(address _collateral) internal view {
        require(
            ICollateralConfig(collateralConfigAddress).isCollateralAllowed(_collateral),
            "Invalid collateral address"
        );
    }

    function _requireCallerIsBorrowerOperationsOrDefaultPool() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool"
        );
    }

    function _requireCallerIsBOorTroveMorSPorRH() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == troveManagerAddress ||
                msg.sender == redemptionHelperAddress ||
                msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BO nor TroveM nor SP nor RH"
        );
    }

    function _requireCallerIsBOorTroveMorSPorLH() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == troveManagerAddress ||
                msg.sender == redemptionHelperAddress ||
                msg.sender == stabilityPoolAddress ||
                msg.sender == liquidationHelperAddress,
            "ActivePool: Caller is neither BO nor TroveM nor SP nor LH"
        );
    }

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress || msg.sender == troveManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager"
        );
    }

    function _requireCallerIsOwnerOrCollateralConfig() internal view {
        require(
            msg.sender == owner() || msg.sender == collateralConfigAddress,
            "ActivePool: Caller is neither owner nor CollateralConfig"
        );
    }
}

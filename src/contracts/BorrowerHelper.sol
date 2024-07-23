// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBorrowerOperations} from "./Interfaces/IBorrowerOperations.sol";
import {ITroveManager} from "./Interfaces/ITroveManager.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {LiquityBase} from "./Dependencies/LiquityBase.sol";
import {IReaperVault} from "./Dependencies/IReaperVault.sol";
import {Ownable} from "./Dependencies/Ownable.sol";

// Helper contract to perform BorrowerOperations functions with Reaper vault tokens as collateral
contract BorrowerHelper is LiquityBase, Ownable, CheckContract {
    using SafeERC20 for IERC20;

    IBorrowerOperations public borrowerOperations;
    ITroveManager public troveManager;
    IERC20 public lusdToken;

    bool public initialized = false;
    bool public paused = false;

    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);
    event TroveManagerAddressChanged(address _troveManagerAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);

    modifier whenNotPaused() {
        require(!paused, "BorrowerHelper: Paused");
        _;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function setAddresses(
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _lusdTokenAddress
    ) external onlyOwner {
        require(!initialized, "Can only initialize once");

        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_lusdTokenAddress);
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        lusdToken = IERC20(_lusdTokenAddress);
        troveManager = ITroveManager(_troveManagerAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);

        initialized = true;
    }

    function openTrove(
        address _collateral,
        uint _collAmount,
        uint _maxFeePercentage,
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external whenNotPaused {
        _collAmount = _transferAndDeposit(_collateral, _collAmount);
        IERC20(_collateral).safeIncreaseAllowance(address(borrowerOperations), _collAmount);
        borrowerOperations.openTroveFor(
            msg.sender,
            _collateral,
            _collAmount,
            _maxFeePercentage,
            _LUSDAmount,
            _upperHint,
            _lowerHint
        );
        lusdToken.safeTransfer(msg.sender, lusdToken.balanceOf(address(this)));
    }

    function closeTrove(address _collateral) external whenNotPaused {
        uint lusdAmount = troveManager.getTroveDebt(msg.sender, _collateral) - LUSD_GAS_COMPENSATION;
        lusdToken.safeTransferFrom(msg.sender, address(this), lusdAmount);
        lusdToken.safeIncreaseAllowance(address(borrowerOperations), lusdAmount);

        borrowerOperations.closeTroveFor(msg.sender, _collateral);
        _withdrawAndTransfer(_collateral);
    }

    function adjustTrove(
        address _collateral,
        uint _maxFeePercentage,
        uint _collTopUp,
        uint _collWithdrawal,
        uint _LUSDChange,
        bool _isDebtIncrease,
        address _upperHint,
        address _lowerHint
    ) external whenNotPaused {
        if (_collTopUp != 0) {
            _collTopUp = _transferAndDeposit(_collateral, _collTopUp);
            IERC20(_collateral).safeIncreaseAllowance(address(borrowerOperations), _collTopUp);
        }
        if (_LUSDChange != 0 && !_isDebtIncrease) {
            lusdToken.safeTransferFrom(msg.sender, address(this), _LUSDChange);
            lusdToken.safeIncreaseAllowance(address(borrowerOperations), _LUSDChange);
        }
        borrowerOperations.adjustTroveFor(
            IBorrowerOperations.Params_adjustTroveFor(
                msg.sender,
                _collateral,
                _maxFeePercentage,
                _collTopUp,
                _collWithdrawal,
                _LUSDChange,
                _isDebtIncrease,
                _upperHint,
                _lowerHint
            )
        );
        if (_isDebtIncrease) {
            lusdToken.safeTransfer(msg.sender, lusdToken.balanceOf(address(this)));
        }
        if (_collWithdrawal != 0) {
            _withdrawAndTransfer(_collateral);
        }
    }

    function claimCollateral(address _collateral) external whenNotPaused {
        borrowerOperations.claimCollateralFor(msg.sender, _collateral);
        _withdrawAndTransfer(_collateral);
    }

    function _transferAndDeposit(
        address _collateral,
        uint _collAmount
    ) private returns (uint shares) {
        IReaperVault vault = IReaperVault(_collateral);
        IERC20 asset = IERC20(vault.asset());

        asset.safeTransferFrom(msg.sender, address(this), _collAmount);
        asset.safeIncreaseAllowance(_collateral, _collAmount);
        shares = vault.deposit(_collAmount, address(this));
    }

    function _withdrawAndTransfer(address _collateral) private {
        IReaperVault vault = IReaperVault(_collateral);
        IERC20 asset = IERC20(vault.asset());

        uint shares = vault.balanceOf(address(this));
        vault.withdraw(shares);

        asset.safeTransfer(msg.sender, asset.balanceOf(address(this)));
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBorrowerOperations} from "./Interfaces/IBorrowerOperations.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {IReaperVault} from "./Dependencies/IReaperVault.sol";
import {Ownable} from "./Dependencies/Ownable.sol";

// Helper contract to perform BorrowerOperations functions with Reaper vault tokens as collateral
contract BorrowerHelper is Ownable, CheckContract {
    using SafeERC20 for IERC20;

    IBorrowerOperations public borrowerOperations;

    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);

    function setAddresses(address _borrowerOperationsAddress) external onlyOwner {
        checkContract(_borrowerOperationsAddress);
        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);

        renounceOwnership();
    }

    function openTrove(
        address _collateral,
        uint _collAmount,
        uint _maxFeePercentage,
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external {
        _collAmount = _transferAndDeposit(_collateral, _collAmount);
        borrowerOperations.openTroveFor(
            msg.sender,
            _collateral,
            _collAmount,
            _maxFeePercentage,
            _LUSDAmount,
            _upperHint,
            _lowerHint
        );
    }

    function closeTrove(address _collateral) external {
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
    ) external {
        if (_isDebtIncrease) {
            _collTopUp = _transferAndDeposit(_collateral, _collTopUp);
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
        if (!_isDebtIncrease) {
            _withdrawAndTransfer(_collateral);
        }
    }

    function claimCollateral(address _collateral) external {
        borrowerOperations.claimCollateral(_collateral);
        _withdrawAndTransfer(_collateral);
    }

    function _transferAndDeposit(
        address _collateral,
        uint _collAmount
    ) private returns (uint shares) {
        IReaperVault vault = IReaperVault(_collateral);
        IERC20 asset = IERC20(vault.asset());

        asset.safeTransferFrom(msg.sender, address(this), _collAmount);
        shares = vault.deposit(_collAmount, address(this));

        IERC20(vault).safeIncreaseAllowance(address(borrowerOperations), shares);
    }

    function _withdrawAndTransfer(address _collateral) private {
        IReaperVault vault = IReaperVault(_collateral);
        IERC20 asset = IERC20(vault.asset());

        uint shares = vault.balanceOf(address(this));
        vault.withdraw(shares);

        asset.safeTransfer(msg.sender, asset.balanceOf(address(this)));
    }
}

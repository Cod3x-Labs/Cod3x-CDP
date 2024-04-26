// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {BaseMath} from "./BaseMath.sol";
import {LiquityMath} from "./LiquityMath.sol";
import {IActivePool} from "../Interfaces/IActivePool.sol";
import {IDefaultPool} from "../Interfaces/IDefaultPool.sol";
import {IPriceFeed} from "../Interfaces/IPriceFeed.sol";
import {ILiquityBase} from "../Interfaces/ILiquityBase.sol";

/*
 * Base contract for TroveManager, BorrowerOperations and StabilityPool. Contains global system constants and
 * common functions.
 */
contract LiquityBase is BaseMath, ILiquityBase {
    uint public constant _100pct = 1000000000000000000; // 1e18 == 100%

    // Amount of LUSD to be locked in gas pool on opening troves
    uint public constant LUSD_GAS_COMPENSATION = 10e18;

    // Minimum amount of net LUSD debt a trove must have
    uint public constant MIN_NET_DEBT = 90e18;
    // uint constant public MIN_NET_DEBT = 0;

    uint public constant PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint public constant BORROWING_FEE_FLOOR = (DECIMAL_PRECISION / 1000) * 5; // 0.5%

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a trove, for the purpose of ICR calculation
    function _getCompositeDebt(uint _debt) internal pure returns (uint) {
        return _debt + LUSD_GAS_COMPENSATION;
    }

    function _getNetDebt(uint _debt) internal pure returns (uint) {
        return _debt - LUSD_GAS_COMPENSATION;
    }

    // Return the amount of ETH to be drawn from a trove's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint _entireColl) internal pure returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function getEntireSystemColl(address _collateral) public view returns (uint entireSystemColl) {
        uint activeColl = activePool.getCollateral(_collateral);
        uint liquidatedColl = defaultPool.getCollateral(_collateral);

        return activeColl + liquidatedColl;
    }

    function getEntireSystemDebt(address _collateral) public view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getLUSDDebt(_collateral);
        uint closedDebt = defaultPool.getLUSDDebt(_collateral);

        return activeDebt + closedDebt;
    }

    function _getTCR(
        address _collateral,
        uint _price,
        uint256 _collateralDecimals
    ) internal view returns (uint TCR) {
        uint entireSystemColl = getEntireSystemColl(_collateral);
        uint entireSystemDebt = getEntireSystemDebt(_collateral);

        TCR = LiquityMath._computeCR(
            entireSystemColl,
            entireSystemDebt,
            _price,
            _collateralDecimals
        );

        return TCR;
    }

    function _checkRecoveryMode(
        address _collateral,
        uint _price,
        uint256 _CCR,
        uint256 _collateralDecimals
    ) internal view returns (bool) {
        uint TCR = _getTCR(_collateral, _price, _collateralDecimals);

        return TCR < _CCR;
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = (_fee * DECIMAL_PRECISION) / _amount;
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }
}

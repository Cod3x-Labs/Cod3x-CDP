// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import "./Interfaces/ICollateralConfig.sol";
import "./Interfaces/IStabilityPool.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ILiquidationHelper.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";

contract LiquidationHelper is LiquityBase, Ownable, ILiquidationHelper {
    ITroveManager public troveManager;
    ICollateralConfig public collateralConfig;
    IStabilityPool public stabilityPool;
    ICollSurplusPool collSurplusPool;
    ISortedTroves public sortedTroves;

    /*
    * --- Variable container structs for liquidations ---
    *
    * These structs are used to hold, return and assign variables inside the liquidation functions,
    * in order to avoid the error: "CompilerError: Stack too deep".
    **/

    struct LocalVariables_OuterLiquidationFunction {
        uint256 collDecimals;
        uint256 collCCR;
        uint256 collMCR;
        uint price;
        uint LUSDInStabPool;
        bool recoveryModeAtStart;
        uint liquidatedDebt;
        uint liquidatedColl;
    }

    struct LocalVariables_InnerSingleLiquidateFunction {
        uint collToLiquidate;
        uint pendingDebtReward;
        uint pendingCollReward;
    }

    struct LocalVariables_LiquidationSequence {
        uint remainingLUSDInStabPool;
        uint i;
        uint ICR;
        uint TCR;
        address user;
        bool backToNormalMode;
        uint entireSystemDebt;
        uint entireSystemColl;
        uint256 collDecimals;
        uint256 collCCR;
        uint256 collMCR;
    }

    struct LiquidationValues {
        uint entireTroveDebt;
        uint entireTroveColl;
        uint collGasCompensation;
        uint LUSDGasCompensation;
        uint debtToOffset;
        uint collToSendToSP;
        uint debtToRedistribute;
        uint collToRedistribute;
        uint collSurplus;
    }

    struct LiquidationTotals {
        uint totalCollInSequence;
        uint totalDebtInSequence;
        uint totalCollGasCompensation;
        uint totalLUSDGasCompensation;
        uint totalDebtToOffset;
        uint totalCollToSendToSP;
        uint totalDebtToRedistribute;
        uint totalCollToRedistribute;
        uint totalCollSurplus;
    }

    function setAddresses(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        ITroveManager _troveManager,
        ICollateralConfig _collateralConfig,
        IStabilityPool _stabilityPool,
        ICollSurplusPool _collSurplusPool,
        IPriceFeed _priceFeed,
        ISortedTroves _sortedTroves
    ) external onlyOwner {
        activePool = _activePool;
        defaultPool = _defaultPool;
        troveManager = _troveManager;
        collateralConfig = _collateralConfig;
        stabilityPool = _stabilityPool;
        collSurplusPool = _collSurplusPool;
        priceFeed = _priceFeed;
        sortedTroves = _sortedTroves;

        renounceOwnership();
    }

    // --- Trove Liquidation functions ---

    // Single liquidation function. Closes the trove if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower, address _collateral, address _caller) external override {
        _requireCallerIsTroveManager();
        _requireTroveIsActive(_borrower, _collateral);

        address[] memory borrowers = new address[](1);
        borrowers[0] = _borrower;
        batchLiquidateTroves(_collateral, borrowers, _caller);
    }

    // --- Inner single liquidation functions ---

    // Liquidate one trove, in Normal Mode.
    function _liquidateNormalMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        address _borrower,
        uint _LUSDInStabPool
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        LocalVariables_InnerSingleLiquidateFunction memory vars;

        (singleLiquidation.entireTroveDebt,
        singleLiquidation.entireTroveColl,
        vars.pendingDebtReward,
        vars.pendingCollReward) = troveManager.getEntireDebtAndColl(_borrower, _collateral);

        troveManager.movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, vars.pendingDebtReward, vars.pendingCollReward);
        troveManager.removeStake(_borrower, _collateral);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entireTroveColl);
        singleLiquidation.LUSDGasCompensation = LUSD_GAS_COMPENSATION;
        uint collToLiquidate = singleLiquidation.entireTroveColl.sub(singleLiquidation.collGasCompensation);

        (singleLiquidation.debtToOffset,
        singleLiquidation.collToSendToSP,
        singleLiquidation.debtToRedistribute,
        singleLiquidation.collToRedistribute) = _getOffsetAndRedistributionVals(singleLiquidation.entireTroveDebt, collToLiquidate, _LUSDInStabPool);

        troveManager.closeTrove(_borrower, _collateral, uint(TroveStatus.closedByLiquidation));
        troveManager.emitTroveLiquidatedAndTroveUpdated(_borrower, _collateral, singleLiquidation.entireTroveDebt, singleLiquidation.entireTroveColl, false);
        return singleLiquidation;
    }

    // Liquidate one trove, in Recovery Mode.
    function _liquidateRecoveryMode(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        address _borrower,
        uint _ICR,
        uint _LUSDInStabPool,
        uint _TCR,
        uint _price,
        uint256 _MCR
    )
        internal
        returns (LiquidationValues memory singleLiquidation)
    {
        LocalVariables_InnerSingleLiquidateFunction memory vars;
        if (troveManager.getTroveOwnersCount(_collateral) <= 1) {return singleLiquidation;} // don't liquidate if last trove
        (singleLiquidation.entireTroveDebt,
        singleLiquidation.entireTroveColl,
        vars.pendingDebtReward,
        vars.pendingCollReward) = troveManager.getEntireDebtAndColl(_borrower, _collateral);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(singleLiquidation.entireTroveColl);
        singleLiquidation.LUSDGasCompensation = LUSD_GAS_COMPENSATION;
        vars.collToLiquidate = singleLiquidation.entireTroveColl.sub(singleLiquidation.collGasCompensation);

        // If ICR <= 100%, purely redistribute the Trove across all active Troves
        if (_ICR <= _100pct) {
            troveManager.movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, vars.pendingDebtReward, vars.pendingCollReward);
            troveManager.removeStake(_borrower, _collateral);
           
            singleLiquidation.debtToOffset = 0;
            singleLiquidation.collToSendToSP = 0;
            singleLiquidation.debtToRedistribute = singleLiquidation.entireTroveDebt;
            singleLiquidation.collToRedistribute = vars.collToLiquidate;

            troveManager.closeTrove(_borrower, _collateral, uint(TroveStatus.closedByLiquidation));
            troveManager.emitTroveLiquidatedAndTroveUpdated(_borrower, _collateral, singleLiquidation.entireTroveDebt, singleLiquidation.entireTroveColl, true);

        // If 100% < ICR < MCR, offset as much as possible, and redistribute the remainder
        } else if ((_ICR > _100pct) && (_ICR < _MCR)) {
            troveManager.movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, vars.pendingDebtReward, vars.pendingCollReward);
            troveManager.removeStake(_borrower, _collateral);

            (singleLiquidation.debtToOffset,
            singleLiquidation.collToSendToSP,
            singleLiquidation.debtToRedistribute,
            singleLiquidation.collToRedistribute) = _getOffsetAndRedistributionVals(singleLiquidation.entireTroveDebt, vars.collToLiquidate, _LUSDInStabPool);

            troveManager.closeTrove(_borrower, _collateral, uint(TroveStatus.closedByLiquidation));
            troveManager.emitTroveLiquidatedAndTroveUpdated(_borrower, _collateral, singleLiquidation.entireTroveDebt, singleLiquidation.entireTroveColl, true);
        /*
        * If MCR <= ICR < current TCR (accounting for the preceding liquidations in the current sequence)
        * and there is LUSD in the Stability Pool, only offset, with no redistribution,
        * but at a capped rate of MCR and only if the whole debt can be liquidated.
        * The remainder due to the capped rate will be claimable as collateral surplus.
        */
        } else if ((_ICR >= _MCR) && (_ICR < _TCR) && (singleLiquidation.entireTroveDebt <= _LUSDInStabPool)) {
            troveManager.movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, vars.pendingDebtReward, vars.pendingCollReward);
            assert(_LUSDInStabPool != 0);

            troveManager.removeStake(_borrower, _collateral);
            uint collDecimals = collateralConfig.getCollateralDecimals(_collateral);
            singleLiquidation = _getCappedOffsetVals(singleLiquidation.entireTroveDebt, singleLiquidation.entireTroveColl, _price, _MCR, collDecimals);

            troveManager.closeTrove(_borrower, _collateral, uint(TroveStatus.closedByLiquidation));
            if (singleLiquidation.collSurplus > 0) {
                collSurplusPool.accountSurplus(_borrower, _collateral, singleLiquidation.collSurplus);
            }

            troveManager.emitTroveLiquidatedAndTroveUpdated(_borrower, _collateral, singleLiquidation.entireTroveDebt, singleLiquidation.collToSendToSP, true);

        } else { // if (_ICR >= _MCR && ( _ICR >= _TCR || singleLiquidation.entireTroveDebt > _LUSDInStabPool))
            LiquidationValues memory zeroVals;
            return zeroVals;
        }

        return singleLiquidation;
    }

    /* In a full liquidation, returns the values for a trove's coll and debt to be offset, and coll and debt to be
    * redistributed to active troves.
    */
    function _getOffsetAndRedistributionVals
    (
        uint _debt,
        uint _coll,
        uint _LUSDInStabPool
    )
        internal
        pure
        returns (uint debtToOffset, uint collToSendToSP, uint debtToRedistribute, uint collToRedistribute)
    {
        if (_LUSDInStabPool > 0) {
        /*
        * Offset as much debt & collateral as possible against the Stability Pool, and redistribute the remainder
        * between all active troves.
        *
        *  If the trove's debt is larger than the deposited LUSD in the Stability Pool:
        *
        *  - Offset an amount of the trove's debt equal to the LUSD in the Stability Pool
        *  - Send a fraction of the trove's collateral to the Stability Pool, equal to the fraction of its offset debt
        *
        */
            debtToOffset = LiquityMath._min(_debt, _LUSDInStabPool);
            collToSendToSP = _coll.mul(debtToOffset).div(_debt);
            debtToRedistribute = _debt.sub(debtToOffset);
            collToRedistribute = _coll.sub(collToSendToSP);
        } else {
            debtToOffset = 0;
            collToSendToSP = 0;
            debtToRedistribute = _debt;
            collToRedistribute = _coll;
        }
    }

    /*
    *  Get its offset coll/debt and ETH gas comp, and close the trove.
    */
    function _getCappedOffsetVals
    (
        uint _entireTroveDebt,
        uint _entireTroveColl,
        uint _price,
        uint256 _MCR,
        uint _collDecimals
    )
        internal
        pure
        returns (LiquidationValues memory singleLiquidation)
    {
        singleLiquidation.entireTroveDebt = _entireTroveDebt;
        singleLiquidation.entireTroveColl = _entireTroveColl;
        uint cappedCollPortion = _entireTroveDebt.mul(_MCR).div(_price);
        if (_collDecimals < LiquityMath.CR_CALCULATION_DECIMALS) {
            cappedCollPortion = cappedCollPortion.div(10 ** (LiquityMath.CR_CALCULATION_DECIMALS - _collDecimals));
        } else if (_collDecimals > LiquityMath.CR_CALCULATION_DECIMALS) {
            cappedCollPortion = cappedCollPortion.mul(10 ** (_collDecimals - LiquityMath.CR_CALCULATION_DECIMALS));
        }

        singleLiquidation.collGasCompensation = _getCollGasCompensation(cappedCollPortion);
        singleLiquidation.LUSDGasCompensation = LUSD_GAS_COMPENSATION;

        singleLiquidation.debtToOffset = _entireTroveDebt;
        singleLiquidation.collToSendToSP = cappedCollPortion.sub(singleLiquidation.collGasCompensation);
        singleLiquidation.collSurplus = _entireTroveColl.sub(cappedCollPortion);
        singleLiquidation.debtToRedistribute = 0;
        singleLiquidation.collToRedistribute = 0;
    }

    /*
    * Liquidate a sequence of troves. Closes a maximum number of n under-collateralized Troves,
    * starting from the one with the lowest collateral ratio in the system, and moving upwards
    */
    function liquidateTroves(address _collateral, uint _n, address _caller) external override {
        _requireCallerIsTroveManager();

        IActivePool activePoolCached = activePool;
        IDefaultPool defaultPoolCached = defaultPool;
        IStabilityPool stabilityPoolCached = stabilityPool;

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        vars.collCCR = collateralConfig.getCollateralCCR(_collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(_collateral);
        vars.price = priceFeed.fetchPrice(_collateral);
        vars.LUSDInStabPool = stabilityPoolCached.getTotalLUSDDeposits();
        vars.recoveryModeAtStart = _checkRecoveryMode(_collateral, vars.price, vars.collCCR, vars.collDecimals);

        // Perform the appropriate liquidation sequence - tally the values, and obtain their totals
        if (vars.recoveryModeAtStart) {
            totals = _getTotalsFromLiquidateTrovesSequence_RecoveryMode(
                activePoolCached,
                defaultPoolCached,
                sortedTroves,
                _collateral,
                vars.price,
                vars.LUSDInStabPool,
                _n
            );
        } else { // if !vars.recoveryModeAtStart
            totals = _getTotalsFromLiquidateTrovesSequence_NormalMode(
                activePoolCached,
                defaultPoolCached,
                _collateral,
                vars.price,
                vars.collMCR,
                vars.LUSDInStabPool,
                _n
            );
        }

        require(totals.totalDebtInSequence > 0, "LiquidationHelper: Total debt in sequence cannot be zero");

        // Move liquidated collateral and LUSD to the appropriate pools
        stabilityPoolCached.offset(_collateral, totals.totalDebtToOffset, totals.totalCollToSendToSP);
        troveManager.redistributeDebtAndColl(
            activePoolCached,
            defaultPoolCached,
            _collateral,
            totals.totalDebtToRedistribute,
            totals.totalCollToRedistribute,
            vars.collDecimals
        );
        if (totals.totalCollSurplus > 0) {
            activePoolCached.sendCollateral(_collateral, address(collSurplusPool), totals.totalCollSurplus);
        }

        // Update system snapshots
        troveManager.updateSystemSnapshots_excludeCollRemainder(activePoolCached, _collateral, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(totals.totalCollSurplus);
        troveManager.emitLiquidationEvent(_collateral, vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalLUSDGasCompensation);

        // Send gas compensation to caller
        troveManager.sendGasCompensation(activePoolCached, _collateral, _caller, totals.totalLUSDGasCompensation, totals.totalCollGasCompensation);
    }

    /*
    * This function is used when the liquidateTroves sequence starts during Recovery Mode. However, it
    * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
    */
    function _getTotalsFromLiquidateTrovesSequence_RecoveryMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        ISortedTroves _sortedTroves,
        address _collateral,
        uint _price,
        uint _LUSDInStabPool,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.collCCR = collateralConfig.getCollateralCCR(_collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(_collateral);
        LiquidationValues memory singleLiquidation;

        vars.remainingLUSDInStabPool = _LUSDInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt(_collateral);
        vars.entireSystemColl = getEntireSystemColl(_collateral);

        vars.user = _sortedTroves.getLast(_collateral);
        address firstUser = _sortedTroves.getFirst(_collateral);
        for (vars.i = 0; vars.i < _n && vars.user != firstUser; vars.i++) {
            // we need to cache it, because current user is likely going to be deleted
            address nextUser = _sortedTroves.getPrev(_collateral, vars.user);

            vars.ICR = troveManager.getCurrentICR(vars.user, _collateral, _price);

            if (!vars.backToNormalMode) {
                // Break the loop if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= vars.collMCR && vars.remainingLUSDInStabPool == 0) { break; }

                vars.TCR = LiquityMath._computeCR(vars.entireSystemColl, vars.entireSystemDebt, _price, vars.collDecimals);

                singleLiquidation = _liquidateRecoveryMode(
                    _activePool,
                    _defaultPool,
                    _collateral,
                    vars.user,
                    vars.ICR,
                    vars.remainingLUSDInStabPool,
                    vars.TCR,
                    _price,
                    vars.collMCR
                );

                // Update aggregate trackers
                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars.entireSystemColl.
                    sub(singleLiquidation.collToSendToSP).
                    sub(singleLiquidation.collGasCompensation).
                    sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price,
                    vars.collDecimals,
                    vars.collCCR
                );
            }
            else if (vars.backToNormalMode && vars.ICR < vars.collMCR) {
                singleLiquidation = _liquidateNormalMode(
                    _activePool,
                    _defaultPool,
                    _collateral,
                    vars.user,
                    vars.remainingLUSDInStabPool
                );

                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            }  else break;  // break if the loop reaches a Trove with ICR >= MCR

            vars.user = nextUser;
        }
    }

    function _getTotalsFromLiquidateTrovesSequence_NormalMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        uint _price,
        uint256 _MCR,
        uint _LUSDInStabPool,
        uint _n
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;
        ISortedTroves sortedTrovesCached = sortedTroves;

        vars.remainingLUSDInStabPool = _LUSDInStabPool;

        for (vars.i = 0; vars.i < _n; vars.i++) {
            vars.user = sortedTrovesCached.getLast(_collateral);
            vars.ICR = troveManager.getCurrentICR(vars.user, _collateral, _price);

            if (vars.ICR < _MCR) {
                singleLiquidation = _liquidateNormalMode(
                    _activePool,
                    _defaultPool,
                    _collateral,
                    vars.user,
                    vars.remainingLUSDInStabPool
                );

                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else break;  // break if the loop reaches a Trove with ICR >= MCR
        }
    }

    /*
    * Attempt to liquidate a custom list of troves (for the specified collateral) provided by the caller.
    */
    function batchLiquidateTroves(address _collateral, address[] memory _troveArray, address _caller) public override {
        require(_troveArray.length != 0, "LiquidationHelper: No troves given");
        _requireCallerIsTroveManager();

        IActivePool activePoolCached = activePool;
        IDefaultPool defaultPoolCached = defaultPool;
        IStabilityPool stabilityPoolCached = stabilityPool;

        LocalVariables_OuterLiquidationFunction memory vars;
        LiquidationTotals memory totals;

        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.collCCR = collateralConfig.getCollateralCCR(_collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(_collateral);
        vars.price = priceFeed.fetchPrice(_collateral);
        vars.LUSDInStabPool = stabilityPoolCached.getTotalLUSDDeposits();
        vars.recoveryModeAtStart = _checkRecoveryMode(_collateral, vars.price, vars.collCCR, vars.collDecimals);

        // Perform the appropriate liquidation sequence - tally values and obtain their totals.
        if (vars.recoveryModeAtStart) {
            totals = _getTotalFromBatchLiquidate_RecoveryMode(
                activePoolCached,
                defaultPoolCached,
                _collateral,
                vars.price,
                vars.LUSDInStabPool,
                _troveArray
            );
        } else {  //  if !vars.recoveryModeAtStart
            totals = _getTotalsFromBatchLiquidate_NormalMode(
                activePoolCached,
                defaultPoolCached,
                _collateral,
                vars.price,
                vars.collMCR,
                vars.LUSDInStabPool,
                _troveArray
            );
        }

        require(totals.totalDebtInSequence > 0, "LiquidationHelper: Total debt in sequence cannot be zero");

        // Move liquidated collateral and LUSD to the appropriate pools
        stabilityPoolCached.offset(_collateral, totals.totalDebtToOffset, totals.totalCollToSendToSP);
        troveManager.redistributeDebtAndColl(
            activePoolCached,
            defaultPoolCached,
            _collateral,
            totals.totalDebtToRedistribute,
            totals.totalCollToRedistribute,
            vars.collDecimals
        );
        if (totals.totalCollSurplus > 0) {
            activePoolCached.sendCollateral(_collateral, address(collSurplusPool), totals.totalCollSurplus);
        }

        // Update system snapshots
        troveManager.updateSystemSnapshots_excludeCollRemainder(activePoolCached, _collateral, totals.totalCollGasCompensation);

        vars.liquidatedDebt = totals.totalDebtInSequence;
        vars.liquidatedColl = totals.totalCollInSequence.sub(totals.totalCollGasCompensation).sub(totals.totalCollSurplus);
        troveManager.emitLiquidationEvent(_collateral, vars.liquidatedDebt, vars.liquidatedColl, totals.totalCollGasCompensation, totals.totalLUSDGasCompensation);

        // Send gas compensation to caller
        troveManager.sendGasCompensation(activePoolCached, _collateral, _caller, totals.totalLUSDGasCompensation, totals.totalCollGasCompensation);
    }

    /*
    * This function is used when the batch liquidation sequence starts during Recovery Mode. However, it
    * handle the case where the system *leaves* Recovery Mode, part way through the liquidation sequence
    */
    function _getTotalFromBatchLiquidate_RecoveryMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        uint _price,
        uint _LUSDInStabPool,
        address[] memory _troveArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.collCCR = collateralConfig.getCollateralCCR(_collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(_collateral);
        LiquidationValues memory singleLiquidation;

        vars.remainingLUSDInStabPool = _LUSDInStabPool;
        vars.backToNormalMode = false;
        vars.entireSystemDebt = getEntireSystemDebt(_collateral);
        vars.entireSystemColl = getEntireSystemColl(_collateral);

        for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
            vars.user = _troveArray[vars.i];
            // Skip non-active troves
            if (troveManager.getTroveStatus(vars.user, _collateral) != uint(TroveStatus.active)) { continue; }
            vars.ICR = troveManager.getCurrentICR(vars.user, _collateral, _price);

            if (!vars.backToNormalMode) {

                // Skip this trove if ICR is greater than MCR and Stability Pool is empty
                if (vars.ICR >= vars.collMCR && vars.remainingLUSDInStabPool == 0) { continue; }

                uint TCR = LiquityMath._computeCR(vars.entireSystemColl, vars.entireSystemDebt, _price, vars.collDecimals);

                singleLiquidation = _liquidateRecoveryMode(
                    _activePool,
                    _defaultPool,
                    _collateral,
                    vars.user,
                    vars.ICR,
                    vars.remainingLUSDInStabPool,
                    TCR,
                    _price,
                    vars.collMCR
                );

                // Update aggregate trackers
                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);
                vars.entireSystemDebt = vars.entireSystemDebt.sub(singleLiquidation.debtToOffset);
                vars.entireSystemColl = vars.entireSystemColl.
                    sub(singleLiquidation.collToSendToSP).
                    sub(singleLiquidation.collGasCompensation).
                    sub(singleLiquidation.collSurplus);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

                vars.backToNormalMode = !_checkPotentialRecoveryMode(
                    vars.entireSystemColl,
                    vars.entireSystemDebt,
                    _price,
                    vars.collDecimals,
                    vars.collCCR
                );
            }

            else if (vars.backToNormalMode && vars.ICR < vars.collMCR) {
                singleLiquidation = _liquidateNormalMode(_activePool, _defaultPool, _collateral, vars.user, vars.remainingLUSDInStabPool);
                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);

            } else continue; // In Normal Mode skip troves with ICR >= MCR
        }
    }

    function _getTotalsFromBatchLiquidate_NormalMode
    (
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        uint _price,
        uint256 _MCR,
        uint _LUSDInStabPool,
        address[] memory _troveArray
    )
        internal
        returns(LiquidationTotals memory totals)
    {
        LocalVariables_LiquidationSequence memory vars;
        LiquidationValues memory singleLiquidation;

        vars.remainingLUSDInStabPool = _LUSDInStabPool;

        for (vars.i = 0; vars.i < _troveArray.length; vars.i++) {
            vars.user = _troveArray[vars.i];
            vars.ICR = troveManager.getCurrentICR(vars.user, _collateral, _price);

            if (vars.ICR < _MCR) {
                singleLiquidation = _liquidateNormalMode(_activePool, _defaultPool, _collateral, vars.user, vars.remainingLUSDInStabPool);
                vars.remainingLUSDInStabPool = vars.remainingLUSDInStabPool.sub(singleLiquidation.debtToOffset);

                // Add liquidation values to their respective running totals
                totals = _addLiquidationValuesToTotals(totals, singleLiquidation);
            }
        }
    }

    // --- Liquidation helper functions ---

    function _addLiquidationValuesToTotals(LiquidationTotals memory oldTotals, LiquidationValues memory singleLiquidation)
        internal
        pure
        returns(LiquidationTotals memory newTotals)
    {
        // Tally all the values with their respective running totals
        newTotals.totalCollGasCompensation = oldTotals.totalCollGasCompensation.add(singleLiquidation.collGasCompensation);
        newTotals.totalLUSDGasCompensation = oldTotals.totalLUSDGasCompensation.add(singleLiquidation.LUSDGasCompensation);
        newTotals.totalDebtInSequence = oldTotals.totalDebtInSequence.add(singleLiquidation.entireTroveDebt);
        newTotals.totalCollInSequence = oldTotals.totalCollInSequence.add(singleLiquidation.entireTroveColl);
        newTotals.totalDebtToOffset = oldTotals.totalDebtToOffset.add(singleLiquidation.debtToOffset);
        newTotals.totalCollToSendToSP = oldTotals.totalCollToSendToSP.add(singleLiquidation.collToSendToSP);
        newTotals.totalDebtToRedistribute = oldTotals.totalDebtToRedistribute.add(singleLiquidation.debtToRedistribute);
        newTotals.totalCollToRedistribute = oldTotals.totalCollToRedistribute.add(singleLiquidation.collToRedistribute);
        newTotals.totalCollSurplus = oldTotals.totalCollSurplus.add(singleLiquidation.collSurplus);

        return newTotals;
    }

    // Check whether or not the system *would be* in Recovery Mode, given an ETH:USD price, and the entire system coll and debt.
    function _checkPotentialRecoveryMode(
        uint _entireSystemColl,
        uint _entireSystemDebt,
        uint _price,
        uint256 _collDecimals,
        uint256 _CCR
    )
        internal
        pure
        returns (bool)
    {
        uint TCR = LiquityMath._computeCR(_entireSystemColl, _entireSystemDebt, _price, _collDecimals);

        return TCR < _CCR;
    }

    // --- 'require' wrapper functions ---
    function _requireTroveIsActive(address _borrower, address _collateral) internal view {
        require(troveManager.getTroveStatus(_borrower, _collateral) == uint(TroveStatus.active),
            "LiquidationHelper: Trove not active");
    }

    function _requireCallerIsTroveManager() internal view {
        require(msg.sender == address(troveManager), "LiquidationHelper: Caller is not TroveManager");
    }
}

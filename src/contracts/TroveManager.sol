// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import "./Interfaces/ICollateralConfig.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ILUSDToken.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Interfaces/ILQTYStaking.sol";
import "./Interfaces/IRedemptionHelper.sol";
import "./Interfaces/ILiquidationHelper.sol";
import "./Dependencies/LiquityBase.sol";
// import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/IERC20.sol";

contract TroveManager is LiquityBase, /*Ownable,*/ CheckContract, ITroveManager {
    // string constant public NAME = "TroveManager";

    address public owner;

    // --- Connected contract declarations ---

    address public borrowerOperationsAddress;

    ICollateralConfig public collateralConfig;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    ILUSDToken public override lusdToken;

    IERC20 public override lqtyToken;

    ILQTYStaking public override lqtyStaking;

    // A doubly linked list of Troves, sorted by their sorted by their collateral ratios
    ISortedTroves public sortedTroves;

    IRedemptionHelper public redemptionHelper;

    ILiquidationHelper public liquidationHelper;

    // --- Data structures ---

    uint constant public SECONDS_IN_ONE_MINUTE = 60;
    /*
     * Half-life of 12h. 12h = 720 min
     * (1/2) = d^720 => d = (1/2)^(1/720)
     */
    uint constant public MINUTE_DECAY_FACTOR = 999037758833783000;
    uint constant public override REDEMPTION_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%
    uint constant public MAX_BORROWING_FEE = DECIMAL_PRECISION / 100 * 5; // 5%

    /*
    * BETA: 18 digit decimal. Parameter by which to divide the redeemed fraction, in order to calc the new base rate from a redemption.
    * Corresponds to (1 / ALPHA) in the white paper.
    */
    uint constant public BETA = 2;

    uint public baseRate;

    // The timestamp of the latest fee operation (redemption or new LUSD issuance)
    uint public lastFeeOperationTime;

    // Store the necessary data for a trove
    struct Trove {
        uint debt;
        uint coll;
        uint stake;
        TroveStatus status;
        uint128 arrayIndex;
    }

    // user => (collateral type => trove)
    mapping (address => mapping (address => Trove)) public Troves;

    mapping (address => uint) public totalStakes;

    // Snapshot of the value of totalStakes for each collateral, taken immediately after the latest liquidation
    mapping (address => uint) public totalStakesSnapshot;

    // Snapshot of the total collateral across the ActivePool and DefaultPool, immediately after the latest liquidation.
    mapping (address => uint) public totalCollateralSnapshot;

    /*
    * L_Collateral and L_LUSDDebt track the sums of accumulated liquidation rewards per unit staked. During its lifetime, each stake earns:
    *
    * A collateral gain of ( stake * [L_Collateral - L_Collateral(0)] )
    * A LUSDDebt increase  of ( stake * [L_LUSDDebt - L_LUSDDebt(0)] )
    *
    * Where L_Collateral(0) and L_LUSDDebt(0) are snapshots of L_Collateral and L_LUSDDebt for the active Trove taken at the instant the stake was made
    */
    mapping (address => uint) public L_Collateral;
    mapping (address => uint) public L_LUSDDebt;

    // Map addresses with active troves to their RewardSnapshot
    // user => (collateral type => reward snapshot))
    mapping (address => mapping (address => RewardSnapshot)) public rewardSnapshots;

    // Object containing the Collateral and LUSD snapshots for a given active trove
    struct RewardSnapshot { uint collAmount; uint LUSDDebt;}

    // Array of all active trove addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
    // collateral type => array of trove owners
    mapping (address => address[]) public TroveOwners;

    // Error trackers for the trove redistribution calculation
    mapping (address => uint) public lastCollateralError_Redistribution;
    mapping (address => uint) public lastLUSDDebtError_Redistribution;

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

    // --- Events ---

    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);
    event PriceFeedAddressChanged(address _newPriceFeedAddress);
    event LUSDTokenAddressChanged(address _newLUSDTokenAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event LQTYTokenAddressChanged(address _lqtyTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);
    event RedemptionHelperAddressChanged(address _redemptionHelperAddress);
    event LiquidationHelperAddressChanged(address _liquidationHelperAddress);

    event Liquidation(address _collateral, uint _liquidatedDebt, uint _liquidatedColl, uint _collGasCompensation, uint _LUSDGasCompensation);
    event TroveUpdated(address indexed _borrower, address _collateral, uint _debt, uint _coll, uint _stake, TroveManagerOperation _operation);
    event TroveLiquidated(address indexed _borrower, address _collateral, uint _debt, uint _coll, TroveManagerOperation _operation);
    event BaseRateUpdated(uint _baseRate);
    event LastFeeOpTimeUpdated(uint _lastFeeOpTime);
    event TotalStakesUpdated(address _collateral, uint _newTotalStakes);
    event SystemSnapshotsUpdated(address _collateral, uint _totalStakesSnapshot, uint _totalCollateralSnapshot);
    event LTermsUpdated(address _collateral, uint _L_Collateral, uint _L_LUSDDebt);
    event TroveSnapshotsUpdated(address _collateral, uint _L_Collateral, uint _L_LUSDDebt);
    event TroveIndexUpdated(address _borrower, address _collateral, uint _newIndex);
    event Redemption(
        address _collateral,
        uint _attemptedLUSDAmount,
        uint _actualLUSDAmount,
        uint _collSent,
        uint _collFee
    );

     enum TroveManagerOperation {
        applyPendingRewards,
        liquidateInNormalMode,
        liquidateInRecoveryMode,
        redeemCollateral
    }

    constructor() public {
        // makeshift ownable implementation to circumvent contract size limit
        owner = msg.sender;
    }

    // --- Dependency setter ---

    function setAddresses(
        address _borrowerOperationsAddress,
        address _collateralConfigAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _lusdTokenAddress,
        address _sortedTrovesAddress,
        address _lqtyTokenAddress,
        address _lqtyStakingAddress,
        address _redemptionHelperAddress,
        address _liquidationHelperAddress
    )
        external
        override
    {
        require(msg.sender == owner);

        checkContract(_borrowerOperationsAddress);
        checkContract(_collateralConfigAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_sortedTrovesAddress);
        checkContract(_lqtyTokenAddress);
        checkContract(_lqtyStakingAddress);
        checkContract(_redemptionHelperAddress);
        checkContract(_liquidationHelperAddress);

        borrowerOperationsAddress = _borrowerOperationsAddress;
        collateralConfig = ICollateralConfig(_collateralConfigAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        lqtyToken = IERC20(_lqtyTokenAddress);
        lqtyStaking = ILQTYStaking(_lqtyStakingAddress);
        redemptionHelper = IRedemptionHelper(_redemptionHelperAddress);
        liquidationHelper = ILiquidationHelper(_liquidationHelperAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit LQTYTokenAddressChanged(_lqtyTokenAddress);
        emit LQTYStakingAddressChanged(_lqtyStakingAddress);
        emit RedemptionHelperAddressChanged(_redemptionHelperAddress);
        emit LiquidationHelperAddressChanged(_liquidationHelperAddress);

        owner = address(0);
    }

    // --- Getters ---

    function getTroveOwnersCount(address _collateral) external view override returns (uint) {
        return TroveOwners[_collateral].length;
    }

    function getTroveFromTroveOwnersArray(address _collateral, uint _index) external view override returns (address) {
        return TroveOwners[_collateral][_index];
    }

    // --- Trove Liquidation functions ---

    // Single liquidation function. Closes the trove if its ICR is lower than the minimum collateral ratio.
    function liquidate(address _borrower, address _collateral) external override {
        liquidationHelper.liquidate(_borrower, _collateral, msg.sender);
    }

    /*
    * Liquidate a sequence of troves. Closes a maximum number of n under-collateralized Troves,
    * starting from the one with the lowest collateral ratio in the system, and moving upwards
    */
    function liquidateTroves(address _collateral, uint _n) external override {
        liquidationHelper.liquidateTroves(_collateral, _n, msg.sender);
    }

    /*
    * Attempt to liquidate a custom list of troves (for the specified collateral) provided by the caller.
    */
    function batchLiquidateTroves(address _collateral, address[] memory _troveArray) public override {
        liquidationHelper.batchLiquidateTroves(_collateral, _troveArray, msg.sender);
    }

    function sendGasCompensation(IActivePool _activePool, address _collateral, address _liquidator, uint _LUSD, uint _collAmount) external override {
        _requireCallerIsLiquidationHelper();
        _sendGasCompensation(_activePool, _collateral, _liquidator, _LUSD, _collAmount);
    }

    function _sendGasCompensation(IActivePool _activePool, address _collateral, address _liquidator, uint _LUSD, uint _collAmount) internal {
        if (_LUSD > 0) {
            lusdToken.returnFromPool(gasPoolAddress, _liquidator, _LUSD);
        }

        if (_collAmount > 0) {
            _activePool.sendCollateral(_collateral, _liquidator, _collAmount);
        }
    }

    function movePendingTroveRewardsToActivePool(IActivePool _activePool, IDefaultPool _defaultPool, address _collateral, uint _LUSD, uint _collAmount) external override {
        _requireCallerIsLiquidationHelper();
        _movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, _LUSD, _collAmount);
    }

    // Move a Trove's pending debt and collateral rewards from distributions, from the Default Pool to the Active Pool
    function _movePendingTroveRewardsToActivePool(IActivePool _activePool, IDefaultPool _defaultPool, address _collateral, uint _LUSD, uint _collAmount) internal {
        _defaultPool.decreaseLUSDDebt(_collateral, _LUSD);
        _activePool.increaseLUSDDebt(_collateral, _LUSD);
        _defaultPool.sendCollateralToActivePool(_collateral, _collAmount);
    }

    function emitTroveLiquidatedAndTroveUpdated(address _borrower, address _collateral, uint _debt, uint _coll, bool _isRecoveryMode) external override {
        _requireCallerIsLiquidationHelper();
        emit TroveLiquidated(_borrower, _collateral, _debt, _coll, _isRecoveryMode ? TroveManagerOperation.liquidateInRecoveryMode :
            TroveManagerOperation.liquidateInNormalMode);
        emit TroveUpdated(_borrower, _collateral, 0, 0, 0, _isRecoveryMode ? TroveManagerOperation.liquidateInRecoveryMode :
            TroveManagerOperation.liquidateInNormalMode);
    }

    function emitLiquidationEvent(address _collateral, uint _liquidatedDebt, uint _liquidatedColl, uint _collGasCompensation, uint _LUSDGasCompensation) external override {
        _requireCallerIsLiquidationHelper();
        emit Liquidation(_collateral, _liquidatedDebt, _liquidatedColl, _collGasCompensation, _LUSDGasCompensation);
    }

    /*
    * Called when a full redemption occurs, and closes the trove.
    * The redeemer swaps (debt - liquidation reserve) LUSD for (debt - liquidation reserve) worth of collateral, so the LUSD liquidation reserve left corresponds to the remaining debt.
    * In order to close the trove, the LUSD liquidation reserve is burned, and the corresponding debt is removed from the active pool.
    * The debt recorded on the trove's struct is zero'd elswhere, in _closeTrove.
    * Any surplus collateral left in the trove, is sent to the Coll surplus pool, and can be later claimed by the borrower.
    */
    function redeemCloseTrove(
        address _borrower,
        address _collateral,
        uint256 _LUSD,
        uint256 _collAmount
    ) external override {
        _requireCallerIsRedemptionHelper();
        lusdToken.burn(gasPoolAddress, _LUSD);
        // Update Active Pool LUSD, and send ETH to account
        activePool.decreaseLUSDDebt(_collateral, _LUSD);

        // send ETH from Active Pool to CollSurplus Pool
        collSurplusPool.accountSurplus(_borrower, _collateral, _collAmount);
        activePool.sendCollateral(_collateral, address(collSurplusPool), _collAmount);

        emit TroveUpdated(_borrower, _collateral, 0, 0, 0, TroveManagerOperation.redeemCollateral);
    }

    function reInsert(address _id, address _collateral, uint256 _newNICR, address _prevId, address _nextId) external override {
        _requireCallerIsRedemptionHelper();
        sortedTroves.reInsert(_id, _collateral, _newNICR, _prevId, _nextId);
    }

    function updateDebtAndCollAndStakesPostRedemption(
        address _borrower,
        address _collateral,
        uint256 _newDebt,
        uint256 _newColl
    ) external override {
        _requireCallerIsRedemptionHelper();
        Troves[_borrower][_collateral].debt = _newDebt;
        Troves[_borrower][_collateral].coll = _newColl;
        _updateStakeAndTotalStakes(_borrower, _collateral);

        emit TroveUpdated(
            _borrower,
            _collateral,
            _newDebt, _newColl,
            Troves[_borrower][_collateral].stake,
            TroveManagerOperation.redeemCollateral
        );
    }

    function burnLUSDAndEmitRedemptionEvent(
        address _redeemer,
        address _collateral,
        uint _attemptedLUSDAmount,
        uint _actualLUSDAmount,
        uint _collSent,
        uint _collFee
    ) external override {
        _requireCallerIsRedemptionHelper();
        lusdToken.burn(_redeemer, _actualLUSDAmount);
        emit Redemption(_collateral, _attemptedLUSDAmount, _actualLUSDAmount, _collSent, _collFee);
    }

    /* Send _LUSDamount LUSD to the system and redeem the corresponding amount of collateral from as many Troves as are needed to fill the redemption
    * request.  Applies pending rewards to a Trove before reducing its debt and coll.
    *
    * Note that if _amount is very large, this function can run out of gas, specially if traversed troves are small. This can be easily avoided by
    * splitting the total _amount in appropriate chunks and calling the function multiple times.
    *
    * Param `_maxIterations` can also be provided, so the loop through Troves is capped (if it’s zero, it will be ignored).This makes it easier to
    * avoid OOG for the frontend, as only knowing approximately the average cost of an iteration is enough, without needing to know the “topology”
    * of the trove list. It also avoids the need to set the cap in stone in the contract, nor doing gas calculations, as both gas price and opcode
    * costs can vary.
    *
    * All Troves that are redeemed from -- with the likely exception of the last one -- will end up with no debt left, therefore they will be closed.
    * If the last Trove does have some remaining debt, it has a finite ICR, and the reinsertion could be anywhere in the list, therefore it requires a hint.
    * A frontend should use getRedemptionHints() to calculate what the ICR of this Trove will be after redemption, and pass a hint for its position
    * in the sortedTroves list along with the ICR value that the hint was found for.
    *
    * If another transaction modifies the list between calling getRedemptionHints() and passing the hints to redeemCollateral(), it
    * is very likely that the last (partially) redeemed Trove would end up with a different ICR than what the hint is for. In this case the
    * redemption will stop after the last completely redeemed Trove and the sender will keep the remaining LUSD amount, which they can attempt
    * to redeem later.
    */
    function redeemCollateral(
        address _collateral,
        uint _LUSDamount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFeePercentage
    )
        external
        override
    {
        redemptionHelper.redeemCollateral(
            _collateral,
            msg.sender,
            _LUSDamount,
            _firstRedemptionHint,
            _upperPartialRedemptionHint,
            _lowerPartialRedemptionHint,
            _partialRedemptionHintNICR,
            _maxIterations,
            _maxFeePercentage
        );
    }

    // --- Helper functions ---

    // Return the nominal collateral ratio (ICR) of a given Trove, without the price. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getNominalICR(address _borrower, address _collateral) public view override returns (uint) {
        (uint currentCollateral, uint currentLUSDDebt) = _getCurrentTroveAmounts(_borrower, _collateral);

        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint NICR = LiquityMath._computeNominalCR(currentCollateral, currentLUSDDebt, collDecimals);
        return NICR;
    }

    // Return the current collateral ratio (ICR) of a given Trove. Takes a trove's pending coll and debt rewards from redistributions into account.
    function getCurrentICR(
        address _borrower,
        address _collateral,
        uint _price
    ) public view override returns (uint) {
        (uint currentCollateral, uint currentLUSDDebt) = _getCurrentTroveAmounts(_borrower, _collateral);

        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint ICR = LiquityMath._computeCR(currentCollateral, currentLUSDDebt, _price, collDecimals);
        return ICR;
    }

    function _getCurrentTroveAmounts(address _borrower, address _collateral) internal view returns (uint, uint) {
        uint pendingCollateralReward = getPendingCollateralReward(_borrower, _collateral);
        uint pendingLUSDDebtReward = getPendingLUSDDebtReward(_borrower, _collateral);

        uint currentCollateral = Troves[_borrower][_collateral].coll.add(pendingCollateralReward);
        uint currentLUSDDebt = Troves[_borrower][_collateral].debt.add(pendingLUSDDebtReward);

        return (currentCollateral, currentLUSDDebt);
    }

    function applyPendingRewards(address _borrower, address _collateral) external override {
        _requireCallerIsBorrowerOperationsOrRedemptionHelper();
        return _applyPendingRewards(activePool, defaultPool, _borrower, _collateral);
    }

    // Add the borrowers's coll and debt rewards earned from redistributions, to their Trove
    function _applyPendingRewards(IActivePool _activePool, IDefaultPool _defaultPool, address _borrower, address _collateral) internal {
        if (hasPendingRewards(_borrower, _collateral)) {
            _requireTroveIsActive(_borrower, _collateral);

            // Compute pending rewards
            uint pendingCollateralReward = getPendingCollateralReward(_borrower, _collateral);
            uint pendingLUSDDebtReward = getPendingLUSDDebtReward(_borrower, _collateral);

            // Apply pending rewards to trove's state
            Troves[_borrower][_collateral].coll = Troves[_borrower][_collateral].coll.add(pendingCollateralReward);
            Troves[_borrower][_collateral].debt = Troves[_borrower][_collateral].debt.add(pendingLUSDDebtReward);

            _updateTroveRewardSnapshots(_borrower, _collateral);

            // Transfer from DefaultPool to ActivePool
            _movePendingTroveRewardsToActivePool(_activePool, _defaultPool, _collateral, pendingLUSDDebtReward, pendingCollateralReward);

            emit TroveUpdated(
                _borrower,
                _collateral,
                Troves[_borrower][_collateral].debt,
                Troves[_borrower][_collateral].coll,
                Troves[_borrower][_collateral].stake,
                TroveManagerOperation.applyPendingRewards
            );
        }
    }

    // Update borrower's snapshots of L_Collateral and L_LUSDDebt to reflect the current values
    function updateTroveRewardSnapshots(address _borrower, address _collateral) external override {
        _requireCallerIsBorrowerOperations();
       return _updateTroveRewardSnapshots(_borrower, _collateral);
    }

    function _updateTroveRewardSnapshots(address _borrower, address _collateral) internal {
        rewardSnapshots[_borrower][_collateral].collAmount = L_Collateral[_collateral];
        rewardSnapshots[_borrower][_collateral].LUSDDebt = L_LUSDDebt[_collateral];
        emit TroveSnapshotsUpdated(_collateral, L_Collateral[_collateral], L_LUSDDebt[_collateral]);
    }

    // Get the borrower's pending accumulated collateral reward, earned by their stake
    function getPendingCollateralReward(address _borrower, address _collateral) public view override returns (uint) {
        uint snapshotCollateral = rewardSnapshots[_borrower][_collateral].collAmount;
        uint rewardPerUnitStaked = L_Collateral[_collateral].sub(snapshotCollateral);

        if ( rewardPerUnitStaked == 0 || Troves[_borrower][_collateral].status != TroveStatus.active) { return 0; }

        uint stake = Troves[_borrower][_collateral].stake;

        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint pendingCollateralReward = stake.mul(rewardPerUnitStaked).div(10**collDecimals);

        return pendingCollateralReward;
    }
    
    // Get the borrower's pending accumulated LUSD reward, earned by their stake
    function getPendingLUSDDebtReward(address _borrower, address _collateral) public view override returns (uint) {
        uint snapshotLUSDDebt = rewardSnapshots[_borrower][_collateral].LUSDDebt;
        uint rewardPerUnitStaked = L_LUSDDebt[_collateral].sub(snapshotLUSDDebt);

        if ( rewardPerUnitStaked == 0 || Troves[_borrower][_collateral].status != TroveStatus.active) { return 0; }

        uint stake = Troves[_borrower][_collateral].stake;

        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint pendingLUSDDebtReward = stake.mul(rewardPerUnitStaked).div(10**collDecimals);

        return pendingLUSDDebtReward;
    }

    function hasPendingRewards(address _borrower, address _collateral) public view override returns (bool) {
        /*
        * A Trove has pending rewards if its snapshot is less than the current rewards per-unit-staked sum:
        * this indicates that rewards have occured since the snapshot was made, and the user therefore has
        * pending rewards
        */
        if (Troves[_borrower][_collateral].status != TroveStatus.active) {return false;}
       
        return (rewardSnapshots[_borrower][_collateral].collAmount < L_Collateral[_collateral]);
    }

    // Return the Troves entire debt and coll, including pending rewards from redistributions.
    function getEntireDebtAndColl(
        address _borrower,
        address _collateral
    )
        public
        view
        override
        returns (uint debt, uint coll, uint pendingLUSDDebtReward, uint pendingCollateralReward)
    {
        debt = Troves[_borrower][_collateral].debt;
        coll = Troves[_borrower][_collateral].coll;

        pendingLUSDDebtReward = getPendingLUSDDebtReward(_borrower, _collateral);
        pendingCollateralReward = getPendingCollateralReward(_borrower, _collateral);

        debt = debt.add(pendingLUSDDebtReward);
        coll = coll.add(pendingCollateralReward);
    }

    function removeStake(address _borrower, address _collateral) external override {
        _requireCallerIsBorrowerOperationsOrRedemptionHelperOrLiquidationHelper();
        return _removeStake(_borrower, _collateral);
    }

    // Remove borrower's stake from the totalStakes sum, and set their stake to 0
    function _removeStake(address _borrower, address _collateral) internal {
        uint stake = Troves[_borrower][_collateral].stake;
        totalStakes[_collateral] = totalStakes[_collateral].sub(stake);
        Troves[_borrower][_collateral].stake = 0;
    }

    function updateStakeAndTotalStakes(address _borrower, address _collateral) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        return _updateStakeAndTotalStakes(_borrower, _collateral);
    }

    // Update borrower's stake based on their latest collateral value
    function _updateStakeAndTotalStakes(address _borrower, address _collateral) internal returns (uint) {
        uint newStake = _computeNewStake(_collateral, Troves[_borrower][_collateral].coll);
        uint oldStake = Troves[_borrower][_collateral].stake;
        Troves[_borrower][_collateral].stake = newStake;

        totalStakes[_collateral] = totalStakes[_collateral].sub(oldStake).add(newStake);
        emit TotalStakesUpdated(_collateral, totalStakes[_collateral]);

        return newStake;
    }

    // Calculate a new stake based on the snapshots of the totalStakes and totalCollateral taken at the last liquidation
    function _computeNewStake(address _collateral, uint _coll) internal view returns (uint) {
        uint stake;
        if (totalCollateralSnapshot[_collateral] == 0) {
            stake = _coll;
        } else {
            /*
            * The following assert() holds true because:
            * - The system always contains >= 1 trove
            * - When we close or liquidate a trove, we redistribute the pending rewards, so if all troves were closed/liquidated,
            * rewards would’ve been emptied and totalCollateralSnapshot would be zero too.
            */
            assert(totalStakesSnapshot[_collateral] > 0);
            stake = _coll.mul(totalStakesSnapshot[_collateral]).div(totalCollateralSnapshot[_collateral]);
        }
        return stake;
    }

    function redistributeDebtAndColl(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        uint _debt,
        uint _coll,
        uint256 _collDecimals
    ) external override {
        _requireCallerIsLiquidationHelper();
        _redistributeDebtAndColl(_activePool, _defaultPool, _collateral, _debt, _coll, _collDecimals);
    }

    function _redistributeDebtAndColl(
        IActivePool _activePool,
        IDefaultPool _defaultPool,
        address _collateral,
        uint _debt,
        uint _coll,
        uint256 _collDecimals
    ) internal {
        if (_debt == 0) { return; }

        /*
        * Add distributed coll and debt rewards-per-unit-staked to the running totals. Division uses a "feedback"
        * error correction, to keep the cumulative error low in the running totals L_Collateral and L_LUSDDebt:
        *
        * 1) Form numerators which compensate for the floor division errors that occurred the last time this
        * function was called.
        * 2) Calculate "per-unit-staked" ratios.
        * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
        * 4) Store these errors for use in the next correction when this function is called.
        * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
        */
        uint collateralNumerator = _coll.mul(10**_collDecimals).add(lastCollateralError_Redistribution[_collateral]);
        uint LUSDDebtNumerator = _debt.mul(10**_collDecimals).add(lastLUSDDebtError_Redistribution[_collateral]);

        // Get the per-unit-staked terms
        uint collateralRewardPerUnitStaked = collateralNumerator.div(totalStakes[_collateral]);
        uint LUSDDebtRewardPerUnitStaked = LUSDDebtNumerator.div(totalStakes[_collateral]);

        lastCollateralError_Redistribution[_collateral] = collateralNumerator.sub(collateralRewardPerUnitStaked.mul(totalStakes[_collateral]));
        lastLUSDDebtError_Redistribution[_collateral] = LUSDDebtNumerator.sub(LUSDDebtRewardPerUnitStaked.mul(totalStakes[_collateral]));

        // Add per-unit-staked terms to the running totals
        L_Collateral[_collateral] = L_Collateral[_collateral].add(collateralRewardPerUnitStaked);
        L_LUSDDebt[_collateral] = L_LUSDDebt[_collateral].add(LUSDDebtRewardPerUnitStaked);

        emit LTermsUpdated(_collateral, L_Collateral[_collateral], L_LUSDDebt[_collateral]);

        // Transfer coll and debt from ActivePool to DefaultPool
        _activePool.decreaseLUSDDebt(_collateral, _debt);
        _defaultPool.increaseLUSDDebt(_collateral, _debt);
        _activePool.sendCollateral(_collateral, address(_defaultPool), _coll);
    }

    function closeTrove(address _borrower, address _collateral, uint256 _closedStatusNum) external override {
        _requireCallerIsBorrowerOperationsOrRedemptionHelperOrLiquidationHelper();
        return _closeTrove(_borrower, _collateral, TroveStatus(_closedStatusNum));
    }

    function _closeTrove(address _borrower, address _collateral, TroveStatus closedStatus) internal {
        assert(closedStatus != TroveStatus.nonExistent && closedStatus != TroveStatus.active);

        uint TroveOwnersArrayLength = TroveOwners[_collateral].length;
        _requireMoreThanOneTroveInSystem(TroveOwnersArrayLength, _collateral);

        Troves[_borrower][_collateral].status = closedStatus;
        Troves[_borrower][_collateral].coll = 0;
        Troves[_borrower][_collateral].debt = 0;

        rewardSnapshots[_borrower][_collateral].collAmount = 0;
        rewardSnapshots[_borrower][_collateral].LUSDDebt = 0;

        _removeTroveOwner(_borrower, _collateral, TroveOwnersArrayLength);
        sortedTroves.remove(_collateral, _borrower);
    }

    /*
    * Updates snapshots of system total stakes and total collateral, excluding a given collateral remainder from the calculation.
    * Used in a liquidation sequence.
    *
    * The calculation excludes a portion of collateral that is in the ActivePool:
    *
    * the total collateral gas compensation from the liquidation sequence
    *
    * The collateral as compensation must be excluded as it is always sent out at the very end of the liquidation sequence.
    */
    function updateSystemSnapshots_excludeCollRemainder(IActivePool _activePool, address _collateral, uint _collRemainder) external override {
        _requireCallerIsLiquidationHelper();
        _updateSystemSnapshots_excludeCollRemainder(_activePool, _collateral, _collRemainder);
    }

    function _updateSystemSnapshots_excludeCollRemainder(IActivePool _activePool, address _collateral, uint _collRemainder) internal {
        totalStakesSnapshot[_collateral] = totalStakes[_collateral];

        uint activeColl = _activePool.getCollateral(_collateral);
        uint liquidatedColl = defaultPool.getCollateral(_collateral);
        totalCollateralSnapshot[_collateral] = activeColl.sub(_collRemainder).add(liquidatedColl);

        emit SystemSnapshotsUpdated(_collateral, totalStakesSnapshot[_collateral], totalCollateralSnapshot[_collateral]);
    }

    // Push the owner's address to the Trove owners list, and record the corresponding array index on the Trove struct
    function addTroveOwnerToArray(address _borrower, address _collateral) external override returns (uint index) {
        _requireCallerIsBorrowerOperations();
        return _addTroveOwnerToArray(_borrower, _collateral);
    }

    function _addTroveOwnerToArray(address _borrower, address _collateral) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 troves. No risk of overflow, since troves have minimum LUSD
        debt of liquidation reserve plus MIN_NET_DEBT. 3e30 LUSD dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Troveowner to the array
        TroveOwners[_collateral].push(_borrower);

        // Record the index of the new Troveowner on their Trove struct
        index = uint128(TroveOwners[_collateral].length.sub(1));
        Troves[_borrower][_collateral].arrayIndex = index;

        return index;
    }

    /*
    * Remove a Trove owner from the TroveOwners array, not preserving array order. Removing owner 'B' does the following:
    * [A B C D E] => [A E C D], and updates E's Trove struct to point to its new array index.
    */
    function _removeTroveOwner(address _borrower, address _collateral, uint TroveOwnersArrayLength) internal {
        TroveStatus troveStatus = Troves[_borrower][_collateral].status;
        // It’s set in caller function `_closeTrove`
        assert(troveStatus != TroveStatus.nonExistent && troveStatus != TroveStatus.active);

        uint128 index = Troves[_borrower][_collateral].arrayIndex;
        uint length = TroveOwnersArrayLength;
        uint idxLast = length.sub(1);

        assert(index <= idxLast);

        address addressToMove = TroveOwners[_collateral][idxLast];

        TroveOwners[_collateral][index] = addressToMove;
        Troves[addressToMove][_collateral].arrayIndex = index;
        emit TroveIndexUpdated(addressToMove, _collateral, index);

        TroveOwners[_collateral].pop();
    }

    // --- Recovery Mode and TCR functions ---

    function getTCR(address _collateral, uint _price) external view override returns (uint) {
        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        return _getTCR(_collateral, _price, collDecimals);
    }

    function checkRecoveryMode(address _collateral, uint _price) external view override returns (bool) {
        uint256 collCCR = collateralConfig.getCollateralCCR(_collateral);
        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        return _checkRecoveryMode(_collateral, _price, collCCR, collDecimals);
    }

    // --- Redemption fee functions ---

    /*
    * This function has two impacts on the baseRate state variable:
    * 1) decays the baseRate based on time passed since last redemption or LUSD borrowing operation.
    * then,
    * 2) increases the baseRate based on the amount redeemed, as a proportion of total supply
    */
    function updateBaseRateFromRedemption(
        uint _collateralDrawn,
        uint _price,
        uint256 _collDecimals,
        uint _collDebt
    ) external override returns (uint) {
        _requireCallerIsRedemptionHelper();
        uint decayedBaseRate = _calcDecayedBaseRate();

        /* Convert the drawn collateral back to LUSD at face value rate (1 LUSD:1 USD), in order to get
        * the fraction of total supply that was redeemed at face value. */
        uint redeemedLUSDFraction = 
            LiquityMath._getScaledCollAmount(_collateralDrawn, _collDecimals).mul(_price).div(_collDebt);

        uint newBaseRate = decayedBaseRate.add(redeemedLUSDFraction.div(BETA));
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
        //assert(newBaseRate <= DECIMAL_PRECISION); // This is already enforced in the line above
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption

        // Update the baseRate state variable
        baseRate = newBaseRate;
        emit BaseRateUpdated(newBaseRate);
        
        _updateLastFeeOpTime();

        return newBaseRate;
    }

    function getRedemptionRate() public view override returns (uint) {
        return _calcRedemptionRate(baseRate);
    }

    function getRedemptionRateWithDecay() public view override returns (uint) {
        return _calcRedemptionRate(_calcDecayedBaseRate());
    }

    function _calcRedemptionRate(uint _baseRate) internal pure returns (uint) {
        return LiquityMath._min(
            REDEMPTION_FEE_FLOOR.add(_baseRate),
            DECIMAL_PRECISION // cap at a maximum of 100%
        );
    }

    function getRedemptionFee(uint _collateralDrawn) public view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRate(), _collateralDrawn);
    }

    function getRedemptionFeeWithDecay(uint _collateralDrawn) external view override returns (uint) {
        return _calcRedemptionFee(getRedemptionRateWithDecay(), _collateralDrawn);
    }

    function _calcRedemptionFee(uint _redemptionRate, uint _collateralDrawn) internal pure returns (uint) {
        uint redemptionFee = _redemptionRate.mul(_collateralDrawn).div(DECIMAL_PRECISION);
        require(redemptionFee < _collateralDrawn);
        return redemptionFee;
    }

    // --- Borrowing fee functions ---

    function getBorrowingRate() public view override returns (uint) {
        return _calcBorrowingRate(baseRate);
    }

    function getBorrowingRateWithDecay() public view override returns (uint) {
        return _calcBorrowingRate(_calcDecayedBaseRate());
    }

    function _calcBorrowingRate(uint _baseRate) internal pure returns (uint) {
        return LiquityMath._min(
            BORROWING_FEE_FLOOR.add(_baseRate),
            MAX_BORROWING_FEE
        );
    }

    function getBorrowingFee(uint _LUSDDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRate(), _LUSDDebt);
    }

    function getBorrowingFeeWithDecay(uint _LUSDDebt) external view override returns (uint) {
        return _calcBorrowingFee(getBorrowingRateWithDecay(), _LUSDDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _LUSDDebt) internal pure returns (uint) {
        return _borrowingRate.mul(_LUSDDebt).div(DECIMAL_PRECISION);
    }


    // Updates the baseRate state variable based on time elapsed since the last redemption or LUSD borrowing operation.
    function decayBaseRateFromBorrowing() external override {
        _requireCallerIsBorrowerOperations();

        uint decayedBaseRate = _calcDecayedBaseRate();
        assert(decayedBaseRate <= DECIMAL_PRECISION);  // The baseRate can decay to 0

        baseRate = decayedBaseRate;
        emit BaseRateUpdated(decayedBaseRate);

        _updateLastFeeOpTime();
    }

    // --- Internal fee functions ---

    // Update the last fee operation time only if time passed >= decay interval. This prevents base rate griefing.
    function _updateLastFeeOpTime() internal {
        uint timePassed = block.timestamp.sub(lastFeeOperationTime);

        if (timePassed >= SECONDS_IN_ONE_MINUTE) {
            lastFeeOperationTime = block.timestamp;
            emit LastFeeOpTimeUpdated(block.timestamp);
        }
    }

    function _calcDecayedBaseRate() internal view returns (uint) {
        uint minutesPassed = _minutesPassedSinceLastFeeOp();
        uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);

        return baseRate.mul(decayFactor).div(DECIMAL_PRECISION);
    }

    function _minutesPassedSinceLastFeeOp() internal view returns (uint) {
        return (block.timestamp.sub(lastFeeOperationTime)).div(SECONDS_IN_ONE_MINUTE);
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsBorrowerOperations() internal view {
        require(msg.sender == borrowerOperationsAddress, "TroveManager: Caller is not BorrowerOperations");
    }

    function _requireCallerIsRedemptionHelper() internal view {
        require(msg.sender == address(redemptionHelper), "TroveManager: Caller is not RedemptionHelper");
    }

    function _requireCallerIsLiquidationHelper() internal view {
        require(msg.sender == address(liquidationHelper), "TroveManager: Caller is not LiquidationHelper");
    }

    function _requireCallerIsBorrowerOperationsOrRedemptionHelperOrLiquidationHelper() internal view {
        require(msg.sender == borrowerOperationsAddress || msg.sender == address(redemptionHelper)
            || msg.sender == address(liquidationHelper), "TroveManager: Caller is neither BO nor RH nor LH");
    }

    function _requireCallerIsBorrowerOperationsOrRedemptionHelper() internal view {
        require(msg.sender == borrowerOperationsAddress || msg.sender == address(redemptionHelper),
            "TroveManager: Caller is neither BO nor RH");
    }

    function _requireTroveIsActive(address _borrower, address _collateral) internal view {
        require(Troves[_borrower][_collateral].status == TroveStatus.active, "TroveManager: Trove not active");
    }

    function _requireMoreThanOneTroveInSystem(uint TroveOwnersArrayLength, address _collateral) internal view {
        require(TroveOwnersArrayLength > 1 && sortedTroves.getSize(_collateral) > 1,
            "TroveManager: Not more than 1 trove in system");
    }

    // --- Trove property getters ---

    function getTroveStatus(address _borrower, address _collateral) external view override returns (uint) {
        return uint(Troves[_borrower][_collateral].status);
    }

    function getTroveStake(address _borrower, address _collateral) external view override returns (uint) {
        return Troves[_borrower][_collateral].stake;
    }

    function getTroveDebt(address _borrower, address _collateral) external view override returns (uint) {
        return Troves[_borrower][_collateral].debt;
    }

    function getTroveColl(address _borrower, address _collateral) external view override returns (uint) {
        return Troves[_borrower][_collateral].coll;
    }

    // --- Trove property setters, called by BorrowerOperations ---

    function setTroveStatus(address _borrower, address _collateral, uint _num) external override {
        _requireCallerIsBorrowerOperations();
        Troves[_borrower][_collateral].status = TroveStatus(_num);
    }

    function increaseTroveColl(address _borrower, address _collateral, uint _collIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        require(collateralConfig.getCollateralDebtLimit(_collateral) != 0,
            "TroveManager: Cannot deposit collateral with debt limit of 0");
        uint newColl = Troves[_borrower][_collateral].coll.add(_collIncrease);
        Troves[_borrower][_collateral].coll = newColl;
        return newColl;
    }

    function decreaseTroveColl(address _borrower, address _collateral, uint _collDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newColl = Troves[_borrower][_collateral].coll.sub(_collDecrease);
        Troves[_borrower][_collateral].coll = newColl;
        return newColl;
    }

    function increaseTroveDebt(address _borrower, address _collateral, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        require(collateralConfig.getCollateralDebtLimit(_collateral) >= getEntireSystemDebt(_collateral).add(_debtIncrease),
            "TroveManager: Debt increase exceeds limit");
        uint newDebt = Troves[_borrower][_collateral].debt.add(_debtIncrease);
        Troves[_borrower][_collateral].debt = newDebt;
        return newDebt;
    }

    function decreaseTroveDebt(address _borrower, address _collateral, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsBorrowerOperations();
        uint newDebt = Troves[_borrower][_collateral].debt.sub(_debtDecrease);
        Troves[_borrower][_collateral].debt = newDebt;
        return newDebt;
    }
}

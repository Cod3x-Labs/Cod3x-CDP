// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICollateralConfig.sol";
import "./Interfaces/ITroveManager.sol";
import "./Interfaces/ILUSDToken.sol";
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ISortedTroves.sol";
import "./Interfaces/ILQTYStaking.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/SafeERC20.sol";

contract BorrowerOperations is LiquityBase, Ownable, CheckContract, IBorrowerOperations {
    using SafeERC20 for IERC20;

    string constant public NAME = "BorrowerOperations";

    bool public initialized = false;

    mapping(address => bool) public exemptFromFee;

    // --- Connected contract declarations ---

    ICollateralConfig public collateralConfig;
    ITroveManager public troveManager;

    address gasPoolAddress;

    ICollSurplusPool collSurplusPool;

    ILQTYStaking public lqtyStaking;
    address public lqtyStakingAddress;

    ILUSDToken public lusdToken;

    // A doubly linked list of Troves, sorted by their collateral ratios
    ISortedTroves public sortedTroves;

    address public leveragerAddress;

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

     struct LocalVariables_adjustTrove {
        uint256 collCCR;
        uint256 collMCR;
        uint256 collDecimals;
        uint price;
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint oldICR;
        uint newICR;
        uint newTCR;
        uint LUSDFee;
        uint newDebt;
        uint newColl;
        uint stake;
        address newUpperHint;
        address newLowerHint;
    }

    struct LocalVariables_openTrove {
        uint256 collCCR;
        uint256 collMCR;
        uint256 collDecimals;
        uint price;
        uint LUSDFee;
        uint netDebt;
        uint compositeDebt;
        uint ICR;
        uint NICR;
        uint stake;
        uint arrayIndex;
        address newUpperHint;
        address newLowerHint;
    }

    struct ContractsCache {
        ITroveManager troveManager;
        IActivePool activePool;
        ILUSDToken lusdToken;
    }

    enum BorrowerOperation {
        openTrove,
        closeTrove,
        adjustTrove
    }

    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);
    event LeveragerAddressChanged(address _leverager);

    event SetFeeExemption(address _borrower, bool _isExempt);

    event TroveCreated(address indexed _borrower, address _collateral, uint arrayIndex);
    event TroveUpdated(address indexed _borrower, address _collateral, uint _debt, uint _coll, uint stake, BorrowerOperation operation);
    event LUSDBorrowingFeePaid(address indexed _borrower, address _collateral, uint _LUSDFee);
    
    // --- Dependency setters ---

    function setAddresses(
        address _collateralConfigAddress,
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _gasPoolAddress,
        address _collSurplusPoolAddress,
        address _priceFeedAddress,
        address _sortedTrovesAddress,
        address _lusdTokenAddress,
        address _lqtyStakingAddress,
        address _leveragerAddress
    )
        external
        override
        onlyOwner
    {
        require(!initialized, "Can only initialize once");

        // This makes impossible to open a trove with zero withdrawn LUSD
        assert(MIN_NET_DEBT > 0);

        checkContract(_collateralConfigAddress);
        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_gasPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_sortedTrovesAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_lqtyStakingAddress);
        checkContract(_leveragerAddress);

        collateralConfig = ICollateralConfig(_collateralConfigAddress);
        troveManager = ITroveManager(_troveManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        gasPoolAddress = _gasPoolAddress;
        collSurplusPool = ICollSurplusPool(_collSurplusPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        sortedTroves = ISortedTroves(_sortedTrovesAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        lqtyStakingAddress = _lqtyStakingAddress;
        lqtyStaking = ILQTYStaking(_lqtyStakingAddress);
        leveragerAddress = _leveragerAddress;

        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit GasPoolAddressChanged(_gasPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit SortedTrovesAddressChanged(_sortedTrovesAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
        emit LQTYStakingAddressChanged(_lqtyStakingAddress);
        emit LeveragerAddressChanged(_leveragerAddress);

        initialized = true;
    }

    function setLeveragerAddress(address _leveragerAddress) external onlyOwner {
        checkContract(_leveragerAddress);
        leveragerAddress = _leveragerAddress;
        emit LeveragerAddressChanged(_leveragerAddress);
    }

    function setExemptFromFee(address _borrower, bool _isExempt) external onlyOwner {
        exemptFromFee[_borrower] = _isExempt;
        emit SetFeeExemption(_borrower, _isExempt);
    }

    // --- Borrower Trove Operations ---

    function openTroveFor(address _borrower, address _collateral, uint _collAmount, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) external override returns (address, address) {
        _requireCallerIsLeverager();
        return _openTrove(_borrower, _collateral, _collAmount, _maxFeePercentage, _LUSDAmount, _upperHint, _lowerHint);
    }

    function openTrove(address _collateral, uint _collAmount, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) external override {
        _openTrove(msg.sender, _collateral, _collAmount, _maxFeePercentage, _LUSDAmount, _upperHint, _lowerHint);
    }

    function _openTrove(address _borrower, address _collateral, uint _collAmount, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) internal returns (address, address) {
        _requireValidCollateralAddress(_collateral);
        _requireSufficientCollateralBalanceAndAllowance(msg.sender, _collateral, _collAmount);
        ContractsCache memory contractsCache = ContractsCache(troveManager, activePool, lusdToken);
        LocalVariables_openTrove memory vars;

        vars.collCCR = collateralConfig.getCollateralCCR(_collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(_collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.price = priceFeed.fetchPrice(_collateral);
        bool isRecoveryMode = _checkRecoveryMode(_collateral, vars.price, vars.collCCR, vars.collDecimals);

        _requireValidMaxFeePercentage(_maxFeePercentage, isRecoveryMode, _borrower);
        _requireTroveisNotActive(contractsCache.troveManager, _borrower, _collateral);

        vars.netDebt = _LUSDAmount;

        if (!isRecoveryMode && !exemptFromFee[_borrower]) {
            vars.LUSDFee = _triggerBorrowingFee(contractsCache.troveManager, contractsCache.lusdToken, _LUSDAmount, _maxFeePercentage);
            vars.netDebt = vars.netDebt.add(vars.LUSDFee);
        }
        _requireAtLeastMinNetDebt(vars.netDebt);

        // ICR is based on the composite debt, i.e. the requested LUSD amount + LUSD borrowing fee + LUSD gas comp.
        vars.compositeDebt = _getCompositeDebt(vars.netDebt);
        assert(vars.compositeDebt > 0);
        
        vars.ICR = LiquityMath._computeCR(_collAmount, vars.compositeDebt, vars.price, vars.collDecimals);
        vars.NICR = LiquityMath._computeNominalCR(_collAmount, vars.compositeDebt, vars.collDecimals);

        if (isRecoveryMode) {
            _requireICRisAboveCCR(vars.ICR, vars.collCCR);
        } else {
            _requireICRisAboveMCR(vars.ICR, vars.collMCR);
            uint newTCR = _getNewTCRFromTroveChange(
                _collateral,
                _collAmount,
                true, // coll increase
                vars.compositeDebt,
                true, // debt increase
                vars.price,
                vars.collDecimals
            );
            _requireNewTCRisAboveCCR(newTCR, vars.collCCR);
        }

        // Set the trove struct's properties
        contractsCache.troveManager.setTroveStatus(_borrower, _collateral, uint(TroveStatus.active));
        contractsCache.troveManager.increaseTroveColl(_borrower, _collateral, _collAmount);
        contractsCache.troveManager.increaseTroveDebt(_borrower, _collateral, vars.compositeDebt);

        contractsCache.troveManager.updateTroveRewardSnapshots(_borrower, _collateral);
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(_borrower, _collateral);

        (vars.newUpperHint, vars.newLowerHint) = sortedTroves.insert(_collateral, _borrower, vars.NICR, _upperHint, _lowerHint);
        vars.arrayIndex = contractsCache.troveManager.addTroveOwnerToArray(_borrower, _collateral);
        emit TroveCreated(_borrower, _collateral, vars.arrayIndex);

        // Pull collateral, move it to the Active Pool, and mint the LUSDAmount to the borrower
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collAmount);
        _activePoolAddColl(contractsCache.activePool, _collateral, _collAmount);
        _withdrawLUSD(contractsCache.activePool, contractsCache.lusdToken, _collateral, msg.sender, _LUSDAmount, vars.netDebt);
        // Move the LUSD gas compensation to the Gas Pool
        _withdrawLUSD(contractsCache.activePool, contractsCache.lusdToken, _collateral, gasPoolAddress, LUSD_GAS_COMPENSATION, LUSD_GAS_COMPENSATION);

        emit TroveUpdated(_borrower, _collateral, vars.compositeDebt, _collAmount, vars.stake, BorrowerOperation.openTrove);
        emit LUSDBorrowingFeePaid(_borrower, _collateral, vars.LUSDFee);

        return (vars.newUpperHint, vars.newLowerHint);
    }

    // Send more collateral to an existing trove
    function addColl(address _collateral, uint _collAmount, address _upperHint, address _lowerHint) external override {
        _requireSufficientCollateralBalanceAndAllowance(msg.sender, _collateral, _collAmount);
        _adjustTrove(Params_adjustTroveFor({
            _borrower: msg.sender,
            _collateral: _collateral,
            _maxFeePercentage: 0,
            _collTopUp: _collAmount,
            _collWithdrawal: 0,
            _LUSDChange: 0,
            _isDebtIncrease: false,
            _upperHint: _upperHint,
            _lowerHint: _lowerHint
        }));
    }

    // Withdraw collateral from a trove
    function withdrawColl(address _collateral, uint _collWithdrawal, address _upperHint, address _lowerHint) external override {
        _adjustTrove(Params_adjustTroveFor({
            _borrower: msg.sender,
            _collateral: _collateral,
            _maxFeePercentage: 0,
            _collTopUp: 0,
            _collWithdrawal: _collWithdrawal,
            _LUSDChange: 0,
            _isDebtIncrease: false,
            _upperHint: _upperHint,
            _lowerHint: _lowerHint
        }));
    }

    // Withdraw LUSD tokens from a trove: mint new LUSD tokens to the owner, and increase the trove's debt accordingly
    function withdrawLUSD(address _collateral, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) external override {
        _adjustTrove(Params_adjustTroveFor({
            _borrower: msg.sender,
            _collateral: _collateral,
            _maxFeePercentage: _maxFeePercentage,
            _collTopUp: 0,
            _collWithdrawal: 0,
            _LUSDChange: _LUSDAmount,
            _isDebtIncrease: true,
            _upperHint: _upperHint,
            _lowerHint: _lowerHint
        }));
    }

    // Repay LUSD tokens to a Trove: Burn the repaid LUSD tokens, and reduce the trove's debt accordingly
    function repayLUSD(address _collateral, uint _LUSDAmount, address _upperHint, address _lowerHint) external override {
        _adjustTrove(Params_adjustTroveFor({
            _borrower: msg.sender,
            _collateral: _collateral,
            _maxFeePercentage: 0,
            _collTopUp: 0,
            _collWithdrawal: 0,
            _LUSDChange: _LUSDAmount,
            _isDebtIncrease: false,
            _upperHint: _upperHint,
            _lowerHint: _lowerHint
        }));
    }

    function adjustTroveFor(Params_adjustTroveFor memory params) external override returns (address, address) {
        _requireCallerIsLeverager();
        if (params._collTopUp != 0) {
            _requireSufficientCollateralBalanceAndAllowance(msg.sender, params._collateral, params._collTopUp);
        }
        return _adjustTrove(params);
    }

    function adjustTrove(address _collateral, uint _maxFeePercentage, uint _collTopUp, uint _collWithdrawal, uint _LUSDChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external override {
        if (_collTopUp != 0) {
            _requireSufficientCollateralBalanceAndAllowance(msg.sender, _collateral, _collTopUp);
        }
        _adjustTrove(Params_adjustTroveFor(msg.sender, _collateral, _maxFeePercentage, _collTopUp, _collWithdrawal, _LUSDChange, _isDebtIncrease, _upperHint, _lowerHint));
    }

    /*
    * _adjustTrove(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal. 
    *
    * It therefore expects either a positive _collTopUp argument, or a positive _collWithdrawal argument.
    *
    * If both are positive, it will revert.
    */
    function _adjustTrove(Params_adjustTroveFor memory params) internal returns (address, address) {
        ContractsCache memory contractsCache = ContractsCache(troveManager, activePool, lusdToken);
        LocalVariables_adjustTrove memory vars;

        vars.collCCR = collateralConfig.getCollateralCCR(params._collateral);
        vars.collMCR = collateralConfig.getCollateralMCR(params._collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(params._collateral);
        vars.price = priceFeed.fetchPrice(params._collateral);
        bool isRecoveryMode = _checkRecoveryMode(params._collateral, vars.price, vars.collCCR, vars.collDecimals);

        if (params._isDebtIncrease) {
            _requireValidMaxFeePercentage(params._maxFeePercentage, isRecoveryMode, params._borrower);
            _requireNonZeroDebtChange(params._LUSDChange);
        }
        _requireSingularCollChange(params._collTopUp, params._collWithdrawal);
        _requireNonZeroAdjustment(params._collTopUp, params._collWithdrawal, params._LUSDChange);
        _requireTroveisActive(contractsCache.troveManager, params._borrower, params._collateral);

        // Confirm the operation is a borrower adjusting their own trove (possibly through the Leverager)
        assert(msg.sender == params._borrower || msg.sender == leveragerAddress);

        contractsCache.troveManager.applyPendingRewards(params._borrower, params._collateral);

        // Get the collChange based on whether or not collateral was sent in the transaction
        (vars.collChange, vars.isCollIncrease) = _getCollChange(params._collTopUp, params._collWithdrawal);

        vars.netDebtChange = params._LUSDChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (params._isDebtIncrease && !isRecoveryMode && !exemptFromFee[params._borrower]) {
            vars.LUSDFee = _triggerBorrowingFee(contractsCache.troveManager, contractsCache.lusdToken, params._LUSDChange, params._maxFeePercentage);
            vars.netDebtChange = vars.netDebtChange.add(vars.LUSDFee); // The raw debt change includes the fee
        }

        vars.debt = contractsCache.troveManager.getTroveDebt(params._borrower, params._collateral);
        vars.coll = contractsCache.troveManager.getTroveColl(params._borrower, params._collateral);
        
        // Get the trove's old ICR before the adjustment, and what its new ICR will be after the adjustment
        vars.oldICR = LiquityMath._computeCR(vars.coll, vars.debt, vars.price, vars.collDecimals);
        vars.newICR = _getNewICRFromTroveChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            params._isDebtIncrease,
            vars.price,
            vars.collDecimals
        );
        assert(params._collWithdrawal <= vars.coll);

        // Check the adjustment satisfies all conditions for the current system mode
        _requireValidAdjustmentInCurrentMode(isRecoveryMode, params._collateral, params._collWithdrawal, params._isDebtIncrease, vars);
            
        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough LUSD
        if (!params._isDebtIncrease && params._LUSDChange > 0) {
            _requireAtLeastMinNetDebt(_getNetDebt(vars.debt).sub(vars.netDebtChange));
            _requireValidLUSDRepayment(vars.debt, vars.netDebtChange);
            _requireSufficientLUSDBalance(contractsCache.lusdToken, msg.sender, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateTroveFromAdjustment(contractsCache.troveManager, params._borrower, params._collateral, vars.collChange, vars.isCollIncrease, vars.netDebtChange, params._isDebtIncrease);
        vars.stake = contractsCache.troveManager.updateStakeAndTotalStakes(params._borrower, params._collateral);

        // Re-insert trove in to the sorted list
        uint newNICR = _getNewNominalICRFromTroveChange(
            vars.coll,
            vars.debt,
            vars.collChange,
            vars.isCollIncrease,
            vars.netDebtChange,
            params._isDebtIncrease,
            vars.collDecimals
        );
        (vars.newUpperHint, vars.newLowerHint) = sortedTroves.reInsert(params._borrower, params._collateral, newNICR, params._upperHint, params._lowerHint);

        emit TroveUpdated(params._borrower, params._collateral, vars.newDebt, vars.newColl, vars.stake, BorrowerOperation.adjustTrove);
        emit LUSDBorrowingFeePaid(params._borrower,  params._collateral, vars.LUSDFee);

        // Use the unmodified _LUSDChange here, as we don't send the fee to the user
        _moveTokensAndCollateralfromAdjustment(
            contractsCache.activePool,
            contractsCache.lusdToken,
            msg.sender,
            params._collateral,
            vars.collChange,
            vars.isCollIncrease,
            params._LUSDChange,
            params._isDebtIncrease,
            vars.netDebtChange
        );

        return (vars.newUpperHint, vars.newLowerHint);
    }

    function closeTroveFor(address _borrower, address _collateral) external override {
        _requireCallerIsLeverager();
        _closeTrove(_borrower, _collateral);
    }

    function closeTrove(address _collateral) external override {
        _closeTrove(msg.sender, _collateral);
    }

    function _closeTrove(address _borrower, address _collateral) internal {
        ITroveManager troveManagerCached = troveManager;
        IActivePool activePoolCached = activePool;
        ILUSDToken lusdTokenCached = lusdToken;

        _requireTroveisActive(troveManagerCached, _borrower, _collateral);
        uint256 collCCR = collateralConfig.getCollateralCCR(_collateral);
        uint256 collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint price = priceFeed.fetchPrice(_collateral);
        _requireNotInRecoveryMode(_collateral, price, collCCR, collDecimals);

        troveManagerCached.applyPendingRewards(_borrower, _collateral);

        uint coll = troveManagerCached.getTroveColl(_borrower, _collateral);
        uint debt = troveManagerCached.getTroveDebt(_borrower, _collateral);

        _requireSufficientLUSDBalance(lusdTokenCached, msg.sender, debt.sub(LUSD_GAS_COMPENSATION));

        uint newTCR = _getNewTCRFromTroveChange(_collateral, coll, false, debt, false, price, collDecimals);
        _requireNewTCRisAboveCCR(newTCR, collCCR);

        troveManagerCached.removeStake(_borrower, _collateral);
        troveManagerCached.closeTrove(_borrower, _collateral, uint(TroveStatus.closedByOwner));

        emit TroveUpdated(_borrower, _collateral, 0, 0, 0, BorrowerOperation.closeTrove);

        // Burn the repaid LUSD from the user's balance and the gas compensation from the Gas Pool
        _repayLUSD(activePoolCached, lusdTokenCached, _collateral, msg.sender, debt.sub(LUSD_GAS_COMPENSATION));
        _repayLUSD(activePoolCached, lusdTokenCached, _collateral, gasPoolAddress, LUSD_GAS_COMPENSATION);

        // Send the collateral back to the user
        activePoolCached.sendCollateral(_collateral, msg.sender, coll);
    }

    /**
     * Claim remaining collateral from a redemption or from a liquidation with ICR > MCR in Recovery Mode
     */
    function claimCollateral(address _collateral) external override {
        // send collateral from CollSurplus Pool to owner
        collSurplusPool.claimColl(msg.sender, _collateral);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(ITroveManager _troveManager, ILUSDToken _lusdToken, uint _LUSDAmount, uint _maxFeePercentage) internal returns (uint) {
        _troveManager.decayBaseRateFromBorrowing(); // decay the baseRate state variable
        uint LUSDFee = _troveManager.getBorrowingFee(_LUSDAmount);

        _requireUserAcceptsFee(LUSDFee, _LUSDAmount, _maxFeePercentage);
        
        // Send fee to LQTY staking contract
        lqtyStaking.increaseF_LUSD(LUSDFee);
        _lusdToken.mint(lqtyStakingAddress, LUSDFee);

        return LUSDFee;
    }

    function _getUSDValue(uint _coll, uint _price, uint256 _collDecimals) internal pure returns (uint) {
        uint usdValue = _price.mul(_coll).div(10**_collDecimals);

        return usdValue;
    }

    function _getCollChange(
        uint _collReceived,
        uint _requestedCollWithdrawal
    )
        internal
        pure
        returns(uint collChange, bool isCollIncrease)
    {
        if (_collReceived != 0) {
            collChange = _collReceived;
            isCollIncrease = true;
        } else {
            collChange = _requestedCollWithdrawal;
        }
    }

    // Update trove's coll and debt based on whether they increase or decrease
    function _updateTroveFromAdjustment
    (
        ITroveManager _troveManager,
        address _borrower,
        address _collateral,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _troveManager.increaseTroveColl(_borrower, _collateral, _collChange)
                                        : _troveManager.decreaseTroveColl(_borrower, _collateral, _collChange);
        uint newDebt = (_isDebtIncrease) ? _troveManager.increaseTroveDebt(_borrower, _collateral, _debtChange)
                                        : _troveManager.decreaseTroveDebt(_borrower, _collateral, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndCollateralfromAdjustment
    (
        IActivePool _activePool,
        ILUSDToken _lusdToken,
        address _borrower,
        address _collateral,
        uint _collChange,
        bool _isCollIncrease,
        uint _LUSDChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    )
        internal
    {
        if (_isDebtIncrease) {
            _withdrawLUSD(_activePool, _lusdToken, _collateral, _borrower, _LUSDChange, _netDebtChange);
        } else {
            _repayLUSD(_activePool, _lusdToken, _collateral, _borrower, _LUSDChange);
        }

        if (_isCollIncrease) {
            IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collChange);
            _activePoolAddColl(_activePool, _collateral, _collChange);
        } else {
            _activePool.sendCollateral(_collateral, _borrower, _collChange);
        }
    }

    // Send collateral to Active Pool and increase its recorded collateral balance
    function _activePoolAddColl(IActivePool _activePool, address _collateral, uint _amount) internal {
        IERC20(_collateral).safeIncreaseAllowance(address(_activePool), _amount);
        _activePool.pullCollateralFromBorrowerOperationsOrDefaultPool(_collateral, _amount);
    }

    // Issue the specified amount of LUSD to _account and increases the total active debt (_netDebtIncrease potentially includes a LUSDFee)
    function _withdrawLUSD(IActivePool _activePool, ILUSDToken _lusdToken, address _collateral, address _account, uint _LUSDAmount, uint _netDebtIncrease) internal {
        _activePool.increaseLUSDDebt(_collateral, _netDebtIncrease);
        _lusdToken.mint(_account, _LUSDAmount);
    }

    // Burn the specified amount of LUSD from _account and decreases the total active debt
    function _repayLUSD(IActivePool _activePool, ILUSDToken _lusdToken, address _collateral, address _account, uint _LUSD) internal {
        _activePool.decreaseLUSDDebt(_collateral, _LUSD);
        _lusdToken.burn(_account, _LUSD);
    }

    // --- 'Require' wrapper functions ---

    function _requireValidCollateralAddress(address _collateral) internal view {
        require(collateralConfig.isCollateralAllowed(_collateral), "BorrowerOps: Invalid collateral address");
    }

    function _requireSufficientCollateralBalanceAndAllowance(address _user, address _collateral, uint _collAmount) internal view {
        require(IERC20(_collateral).balanceOf(_user) >= _collAmount, "BorrowerOperations: Insufficient user collateral balance");
        require(IERC20(_collateral).allowance(_user, address(this)) >= _collAmount, "BorrowerOperations: Insufficient collateral allowance");
    }

    function _requireSingularCollChange(uint _collTopUp, uint _collWithdrawal) internal pure {
        require(_collTopUp == 0 || _collWithdrawal == 0, "BorrowerOperations: Cannot withdraw and add coll");
    }

    function _requireNonZeroAdjustment(uint _collTopUp, uint _collWithdrawal, uint _LUSDChange) internal pure {
        require(_collTopUp != 0 || _collWithdrawal != 0 || _LUSDChange != 0, "BorrowerOps: There must be either a collateral change or a debt change");
    }

    function _requireTroveisActive(ITroveManager _troveManager, address _borrower, address _collateral) internal view {
        uint status = _troveManager.getTroveStatus(_borrower, _collateral);
        require(status == uint(TroveStatus.active), "BorrowerOps: Trove does not exist or is closed");
    }

    function _requireTroveisNotActive(ITroveManager _troveManager, address _borrower, address _collateral) internal view {
        uint status = _troveManager.getTroveStatus(_borrower, _collateral);
        require(status != uint(TroveStatus.active), "BorrowerOps: Trove is active");
    }

    function _requireNonZeroDebtChange(uint _LUSDChange) internal pure {
        require(_LUSDChange > 0, "BorrowerOps: Debt increase requires non-zero debtChange");
    }
   
    function _requireNotInRecoveryMode(
        address _collateral,
        uint _price,
        uint256 _CCR,
        uint256 _collateralDecimals
    ) internal view {
        require(
            !_checkRecoveryMode(_collateral, _price, _CCR, _collateralDecimals),
            "BorrowerOps: Operation not permitted during Recovery Mode"
        );
    }

    function _requireNoCollWithdrawal(uint _collWithdrawal) internal pure {
        require(_collWithdrawal == 0, "BorrowerOps: Collateral withdrawal not permitted Recovery Mode");
    }

    function _requireValidAdjustmentInCurrentMode 
    (
        bool _isRecoveryMode,
        address _collateral,
        uint _collWithdrawal,
        bool _isDebtIncrease, 
        LocalVariables_adjustTrove memory _vars
    ) 
        internal 
        view 
    {
        /* 
        *In Recovery Mode, only allow:
        *
        * - Pure collateral top-up
        * - Pure debt repayment
        * - Collateral top-up with debt repayment
        * - A debt increase combined with a collateral top-up which makes the ICR >= 150% and improves the ICR (and by extension improves the TCR).
        *
        * In Normal Mode, ensure:
        *
        * - The new ICR is above MCR
        * - The adjustment won't pull the TCR below CCR
        */
        if (_isRecoveryMode) {
            _requireNoCollWithdrawal(_collWithdrawal);
            if (_isDebtIncrease) {
                _requireICRisAboveCCR(_vars.newICR, _vars.collCCR);
                _requireNewICRisAboveOldICR(_vars.newICR, _vars.oldICR);
            }       
        } else { // if Normal Mode
            _requireICRisAboveMCR(_vars.newICR, _vars.collMCR);
            _vars.newTCR = _getNewTCRFromTroveChange(
                _collateral,
                _vars.collChange,
                _vars.isCollIncrease,
                _vars.netDebtChange,
                _isDebtIncrease,
                _vars.price,
                _vars.collDecimals
            );
            _requireNewTCRisAboveCCR(_vars.newTCR, _vars.collCCR);
        }
    }

    function _requireICRisAboveMCR(uint _newICR, uint256 _MCR) internal pure {
        require(_newICR >= _MCR, "BorrowerOps: An operation that would result in ICR < MCR is not permitted");
    }

    function _requireICRisAboveCCR(uint _newICR, uint256 _CCR) internal pure {
        require(_newICR >= _CCR, "BorrowerOps: Operation must leave trove with ICR >= CCR");
    }

    function _requireNewICRisAboveOldICR(uint _newICR, uint _oldICR) internal pure {
        require(_newICR >= _oldICR, "BorrowerOps: Cannot decrease your Trove's ICR in Recovery Mode");
    }

    function _requireNewTCRisAboveCCR(uint _newTCR, uint256 _CCR) internal pure {
        require(_newTCR >= _CCR, "BorrowerOps: An operation that would result in TCR < CCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require (_netDebt >= MIN_NET_DEBT, "BorrowerOps: Trove's net debt must be greater than minimum");
    }

    function _requireValidLUSDRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= _currentDebt.sub(LUSD_GAS_COMPENSATION), "BorrowerOps: Amount repaid must not be larger than the Trove's debt");
    }

    function _requireCallerIsLeverager() internal view {
        require(msg.sender == leveragerAddress, "BorrowerOps: Caller is not Leverager");
    }

     function _requireSufficientLUSDBalance(ILUSDToken _lusdToken, address _borrower, uint _debtRepayment) internal view {
        require(_lusdToken.balanceOf(_borrower) >= _debtRepayment, "BorrowerOps: Caller doesnt have enough LUSD to make repayment");
    }

    function _requireValidMaxFeePercentage(uint _maxFeePercentage, bool _isRecoveryMode, address _borrower) internal view {
        if (_isRecoveryMode || exemptFromFee[_borrower]) {
            require(_maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must less than or equal to 100%");
        } else {
            require(_maxFeePercentage >= BORROWING_FEE_FLOOR && _maxFeePercentage <= DECIMAL_PRECISION,
                "Max fee percentage must be between 0.5% and 100%");
        }
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewNominalICRFromTroveChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint256 _collateralDecimals
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newNICR = LiquityMath._computeNominalCR(newColl, newDebt, _collateralDecimals);
        return newNICR;
    }

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromTroveChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price,
        uint256 _collateralDecimals
    )
        pure
        internal
        returns (uint)
    {
        (uint newColl, uint newDebt) = _getNewTroveAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newICR = LiquityMath._computeCR(newColl, newDebt, _price, _collateralDecimals);
        return newICR;
    }

    function _getNewTroveAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll.add(_collChange) :  _coll.sub(_collChange);
        newDebt = _isDebtIncrease ? _debt.add(_debtChange) : _debt.sub(_debtChange);

        return (newColl, newDebt);
    }

    function _getNewTCRFromTroveChange
    (
        address _collateral,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price,
        uint256 _collateralDecimals
    )
        internal
        view
        returns (uint)
    {
        uint totalColl = getEntireSystemColl(_collateral);
        uint totalDebt = getEntireSystemDebt(_collateral);

        totalColl = _isCollIncrease ? totalColl.add(_collChange) : totalColl.sub(_collChange);
        totalDebt = _isDebtIncrease ? totalDebt.add(_debtChange) : totalDebt.sub(_debtChange);

        uint newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price, _collateralDecimals);
        return newTCR;
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }
}

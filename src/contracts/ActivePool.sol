// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import './Interfaces/IActivePool.sol';
import "./Interfaces/ICollateralConfig.sol";
import './Interfaces/IDefaultPool.sol';
import "./Interfaces/ICollSurplusPool.sol";
import "./Interfaces/ITroveManager.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/console.sol";
import "./Dependencies/SafeERC20.sol";
import "./Dependencies/IReaperVaultV2.sol";

/*
 * The Active Pool holds the collateral and LUSD debt for each collateral (but not LUSD tokens) for all active troves.
 *
 * When a trove is liquidated, it's collateral and LUSD debt are transferred from the Active Pool, to either the
 * Stability Pool, the Default Pool, or both, depending on the liquidation conditions.
 *
 */
contract ActivePool is Ownable, CheckContract, IActivePool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string constant public NAME = "ActivePool";

    bool public addressesSet = false;
    address public collateralConfigAddress;
    address public borrowerOperationsAddress;
    address public troveManagerAddress;
    address public redemptionHelperAddress;
    address public liquidationHelperAddress;
    address public stabilityPoolAddress;
    address public defaultPoolAddress;
    address public collSurplusPoolAddress;
    address public treasuryAddress;
    mapping (address => uint256) internal collAmount;  // collateral => amount tracker
    mapping (address => uint256) internal LUSDDebt;  // collateral => corresponding debt tracker

    mapping (address => uint256) public yieldingPercentage; // collateral => % to use for yield farming (in BPS, <= 10k)
    mapping (address => uint256) public yieldingAmount; // collateral => actual wei amount being used for yield farming
    mapping (address => address) public yieldGenerator; // collateral => corresponding ReaperVaultV2
    mapping (address => uint256) public yieldClaimThreshold; // collateral => minimum wei amount of yield to claim and redistribute
    
    uint256 public yieldingPercentageDrift = 100; // rebalance iff % is off by more than 100 BPS

    // --- Events ---

    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);
    event BorrowerOperationsAddressChanged(address _newBorrowerOperationsAddress);
    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event RedemptionHelperAddressChanged(address _redemptionHelperAddress);
    event LiquidationHelperAddressChanged(address _liquidationHelperAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event TreasuryAddressChanged(address _treasuryAddress);
    event ActivePoolLUSDDebtUpdated(address _collateral, uint _LUSDDebt);
    event ActivePoolCollateralBalanceUpdated(address _collateral, uint _amount);
    event YieldingPercentageUpdated(address _collateral, uint256 _bps);
    event YieldingPercentageDriftUpdated(uint256 _driftBps);
    event YieldClaimThresholdUpdated(address _collateral, uint256 _threshold);

    // --- Contract setters ---

    function setAddresses(
        address _collateralConfigAddress,
        address _borrowerOperationsAddress,
        address _troveManagerAddress,
        address _redemptionHelperAddress,
        address _liquidationHelperAddress,
        address _stabilityPoolAddress,
        address _defaultPoolAddress,
        address _collSurplusPoolAddress,
        address _treasuryAddress,
        address[] calldata _reaperVaults
    )
        external
        onlyOwner
    {
        require(!addressesSet, "Can call setAddresses only once");

        checkContract(_collateralConfigAddress);
        checkContract(_borrowerOperationsAddress);
        checkContract(_troveManagerAddress);
        checkContract(_redemptionHelperAddress);
        checkContract(_liquidationHelperAddress);
        checkContract(_stabilityPoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_collSurplusPoolAddress);
        checkContract(_treasuryAddress);

        collateralConfigAddress = _collateralConfigAddress;
        borrowerOperationsAddress = _borrowerOperationsAddress;
        troveManagerAddress = _troveManagerAddress;
        redemptionHelperAddress = _redemptionHelperAddress;
        liquidationHelperAddress = _liquidationHelperAddress;
        stabilityPoolAddress = _stabilityPoolAddress;
        defaultPoolAddress = _defaultPoolAddress;
        collSurplusPoolAddress = _collSurplusPoolAddress;
        treasuryAddress = _treasuryAddress;

        address[] memory collaterals = ICollateralConfig(collateralConfigAddress).getAllowedCollaterals();
        uint256 numCollaterals = collaterals.length;
        require(numCollaterals == _reaperVaults.length, "Vaults array length must match number of collaterals");
        for(uint256 i = 0; i < numCollaterals; i++) {
            address collateral = collaterals[i];
            address vault = _reaperVaults[i];
            require(IReaperVaultV2(vault).token() == collateral, "Vault asset must be collateral");
            yieldGenerator[collateral] = vault;
        }

        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit RedemptionHelperAddressChanged(_redemptionHelperAddress);
        emit LiquidationHelperAddressChanged(_liquidationHelperAddress);
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit CollSurplusPoolAddressChanged(_collSurplusPoolAddress);
        emit TreasuryAddressChanged(_treasuryAddress);

        addressesSet = true;
    }

    function setYieldGenerator(address _collateral, address _vault) external override {
        _requireCallerIsOwnerOrCollateralConfig();
        require(yieldingAmount[_collateral] == 0, "All assets not withdrawn from previous vault");
        require(IReaperVaultV2(_vault).token() == _collateral, "Vault asset must be collateral");
        yieldGenerator[_collateral] = _vault;
    }

    function setYieldingPercentage(address _collateral, uint256 _bps) external onlyOwner {
        _requireValidCollateralAddress(_collateral);
        require(_bps <= 10_000, "Invalid BPS value");
        yieldingPercentage[_collateral] = _bps;
        emit YieldingPercentageUpdated(_collateral, _bps);
    }

    function setYieldingPercentageDrift(uint256 _driftBps) external onlyOwner {
        require(_driftBps <= 500, "Exceeds max allowed value of 500 BPS");
        yieldingPercentageDrift = _driftBps;
        emit YieldingPercentageDriftUpdated(_driftBps);
    }

    function setYieldClaimThreshold(address _collateral, uint256 _threshold) external onlyOwner {
        _requireValidCollateralAddress(_collateral);
        yieldClaimThreshold[_collateral] = _threshold;
        emit YieldClaimThresholdUpdated(_collateral, _threshold);
    }

    function updateTreasury(address _newTreasuryAddress) external onlyOwner {
        checkContract(_newTreasuryAddress);
        treasuryAddress = _newTreasuryAddress;
        emit TreasuryAddressChanged(_newTreasuryAddress);
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
        _rebalance(_collateral, _amount);
        collAmount[_collateral] = collAmount[_collateral].sub(_amount);
        emit ActivePoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);
        emit CollateralSent(_collateral, _account, _amount);

        if (_account == defaultPoolAddress) {
            IERC20(_collateral).safeIncreaseAllowance(defaultPoolAddress, _amount);
            IDefaultPool(defaultPoolAddress).pullCollateralFromActivePool(_collateral, _amount);
        } else if (_account == collSurplusPoolAddress) {
            IERC20(_collateral).safeIncreaseAllowance(collSurplusPoolAddress, _amount);
            ICollSurplusPool(collSurplusPoolAddress).pullCollateralFromActivePool(_collateral, _amount);
        } else {
            IERC20(_collateral).safeTransfer(_account, _amount);
        }
    }

    function increaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBOorTroveM();
        LUSDDebt[_collateral] = LUSDDebt[_collateral].add(_amount);
        ActivePoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function decreaseLUSDDebt(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBOorTroveMorSPorRH();
        LUSDDebt[_collateral] = LUSDDebt[_collateral].sub(_amount);
        ActivePoolLUSDDebtUpdated(_collateral, LUSDDebt[_collateral]);
    }

    function pullCollateralFromBorrowerOperationsOrDefaultPool(address _collateral, uint _amount) external override {
        _requireValidCollateralAddress(_collateral);
        _requireCallerIsBorrowerOperationsOrDefaultPool();
        collAmount[_collateral] = collAmount[_collateral].add(_amount);
        emit ActivePoolCollateralBalanceUpdated(_collateral, collAmount[_collateral]);

        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);
        _rebalance(_collateral, 0);
    }

    function manualRebalance(address _collateral, uint256 _simulatedAmountLeavingPool) external onlyOwner {
        _requireValidCollateralAddress(_collateral);
        _rebalance(_collateral, _simulatedAmountLeavingPool);
    }

    // Due to "stack too deep" error
    struct LocalVariables_rebalance {
        uint256 currentAllocated;
        IReaperVaultV2 yieldGenerator;
        uint256 vaultBalance;
        uint256 vaultTotalSupply;
        uint256 ownedShares;
        uint256 sharesToAssets;
        uint256 profit;
        uint256 finalBalance;
        uint256 percentOfFinalBal;
        uint256 yieldingPercentage;
        uint256 toDeposit;
        uint256 toWithdraw;
        uint256 yieldingAmount;
        uint256 finalYieldingAmount;
        int256 netAssetMovement;
        uint256 treasurySplit;
        uint256 stakingSplit;
        uint256 stabilityPoolSplit;
    }

    function _rebalance(address _collateral, uint256 _amountLeavingPool) internal {
        LocalVariables_rebalance memory vars;

        // how much has been allocated as per our internal records?
        vars.currentAllocated = yieldingAmount[_collateral];
        
        // what is the present value of our shares?
        vars.yieldGenerator = IReaperVaultV2(yieldGenerator[_collateral]);
        vars.vaultBalance = vars.yieldGenerator.balance();
        vars.vaultTotalSupply = vars.yieldGenerator.totalSupply();
        vars.ownedShares = vars.yieldGenerator.balanceOf(address(this));
        if (vars.ownedShares != 0) {
            // ownerShares != 0 implies totalSupply != 0
            vars.sharesToAssets = vars.vaultBalance.mul(vars.ownedShares).div(vars.vaultTotalSupply);
        }

        // if we have profit that's more than the threshold, record it for withdrawal and redistribution
        vars.profit = vars.sharesToAssets.sub(vars.currentAllocated);
        if (vars.profit < yieldClaimThreshold[_collateral]) {
            vars.profit = 0;
        }
        
        // what % of the final pool balance would the current allocation be?
        vars.finalBalance = collAmount[_collateral].sub(_amountLeavingPool);
        vars.percentOfFinalBal = vars.finalBalance == 0 ? uint256(-1) : vars.currentAllocated.mul(10_000).div(vars.finalBalance);

        // if abs(percentOfFinalBal - yieldingPercentage) > drift, we will need to deposit more or withdraw some
        vars.yieldingPercentage = yieldingPercentage[_collateral];
        vars.finalYieldingAmount = vars.finalBalance.mul(vars.yieldingPercentage).div(10_000);
        vars.yieldingAmount = yieldingAmount[_collateral];
        if (vars.percentOfFinalBal > vars.yieldingPercentage && vars.percentOfFinalBal.sub(vars.yieldingPercentage) > yieldingPercentageDrift) {
            // we will end up overallocated, withdraw some
            vars.toWithdraw = vars.currentAllocated.sub(vars.finalYieldingAmount);
            vars.yieldingAmount = vars.yieldingAmount.sub(vars.toWithdraw);
            yieldingAmount[_collateral] = vars.yieldingAmount;
        } else if(vars.percentOfFinalBal < vars.yieldingPercentage && vars.yieldingPercentage.sub(vars.percentOfFinalBal) > yieldingPercentageDrift) {
            // we will end up underallocated, deposit more
            vars.toDeposit = vars.finalYieldingAmount.sub(vars.currentAllocated);
            vars.yieldingAmount = vars.yieldingAmount.add(vars.toDeposit);
            yieldingAmount[_collateral] = vars.yieldingAmount;
        }

        // + means deposit, - means withdraw
        vars.netAssetMovement = int256(vars.toDeposit) - int256(vars.toWithdraw) - int256(vars.profit);
        if (vars.netAssetMovement > 0) {
            IERC20(_collateral).safeIncreaseAllowance(address(vars.yieldGenerator), uint256(vars.netAssetMovement));
            vars.yieldGenerator.deposit(uint256(vars.netAssetMovement));
        } else if (vars.netAssetMovement < 0) {
            vars.yieldGenerator.withdraw(uint256(-vars.netAssetMovement).mul(vars.vaultTotalSupply).div(vars.vaultBalance));
        }

        // if we recorded profit, recalculate it for precision and distribute
        if (vars.profit != 0) {
            // profit is ultimately (coll at hand) + (coll allocated to yield generator) - (recorded total coll Amount in pool)
            vars.profit = IERC20(_collateral).balanceOf(address(this)).add(vars.yieldingAmount).sub(collAmount[_collateral]);
            if (vars.profit != 0) {
                IERC20(_collateral).safeTransfer(treasuryAddress, vars.profit);
            }
        }
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
            msg.sender == borrowerOperationsAddress ||
            msg.sender == defaultPoolAddress,
            "ActivePool: Caller is neither BO nor Default Pool");
    }

    function _requireCallerIsBOorTroveMorSPorRH() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress ||
            msg.sender == redemptionHelperAddress ||
            msg.sender == stabilityPoolAddress,
            "ActivePool: Caller is neither BO nor TroveM nor SP nor RH");
    }

    function _requireCallerIsBOorTroveMorSPorLH() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress ||
            msg.sender == redemptionHelperAddress ||
            msg.sender == stabilityPoolAddress ||
            msg.sender == liquidationHelperAddress,
            "ActivePool: Caller is neither BO nor TroveM nor SP nor LH");
    }

    function _requireCallerIsBOorTroveM() internal view {
        require(
            msg.sender == borrowerOperationsAddress ||
            msg.sender == troveManagerAddress,
            "ActivePool: Caller is neither BorrowerOperations nor TroveManager");
    }

    function _requireCallerIsOwnerOrCollateralConfig() internal view {
        require(msg.sender == owner() || msg.sender == collateralConfigAddress,
            "ActivePool: Caller is neither owner nor CollateralConfig");
    }
}

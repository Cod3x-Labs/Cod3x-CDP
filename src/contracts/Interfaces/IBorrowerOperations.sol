// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

// Common interface for the Trove Manager.
interface IBorrowerOperations {

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

    struct Params_adjustTroveFor {
        address _borrower;
        address _collateral;
        uint _maxFeePercentage;
        uint _collTopUp;
        uint _collWithdrawal;
        uint _LUSDChange;
        bool _isDebtIncrease;
        address _upperHint;
        address _lowerHint;
    }

    // --- Events ---

    event TroveManagerAddressChanged(address _newTroveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event GasPoolAddressChanged(address _gasPoolAddress);
    event CollSurplusPoolAddressChanged(address _collSurplusPoolAddress);
    event PriceFeedAddressChanged(address  _newPriceFeedAddress);
    event SortedTrovesAddressChanged(address _sortedTrovesAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);
    event LQTYStakingAddressChanged(address _lqtyStakingAddress);

    event TroveCreated(address indexed _borrower, address _collateral, uint arrayIndex);
    event TroveUpdated(address indexed _borrower, address _collateral, uint _debt, uint _coll, uint stake, uint8 operation);
    event LUSDBorrowingFeePaid(address indexed _borrower, address _collateral, uint _LUSDFee);

    // --- Functions ---

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
    ) external;

    function openTrove(address _collateral, uint _collAmount, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) external;
    function openTroveFor(address _borrower, address _collateral, uint _collAmount, uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint) external returns (address, address);

    function addColl(address _collateral, uint _collAmount, address _upperHint, address _lowerHint) external;
    function withdrawColl(address _collateral, uint _amount, address _upperHint, address _lowerHint) external;

    function withdrawLUSD(address _collateral, uint _maxFee, uint _amount, address _upperHint, address _lowerHint) external;
    function repayLUSD(address _collateral, uint _amount, address _upperHint, address _lowerHint) external;

    function closeTrove(address _collateral) external;
    function closeTroveFor(address _borrower, address _collateral) external;

    function adjustTrove(address _collateral, uint _maxFeePercentage, uint _collTopUp, uint _collWithdrawal, uint _LUSDChange, bool _isDebtIncrease, address _upperHint, address _lowerHint) external;
    function adjustTroveFor(Params_adjustTroveFor memory) external returns (address, address);

    function claimCollateral(address _collateral) external;

    function getCompositeDebt(uint _debt) external pure returns (uint);
}

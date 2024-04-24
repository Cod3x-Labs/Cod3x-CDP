// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../Dependencies/LiquityMath.sol";
import "../Dependencies/IERC20.sol";
import "../Interfaces/IBorrowerOperations.sol";
import "../Interfaces/ICollateralConfig.sol";
import "../Interfaces/ITroveManager.sol";
import "../Interfaces/IStabilityPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "./BorrowerOperationsScript.sol";
import "./ERC20TransferScript.sol";
import "../Dependencies/SafeERC20.sol";

contract BorrowerWrappersScript is BorrowerOperationsScript, ERC20TransferScript {
    using SafeERC20 for IERC20;

    string public constant NAME = "BorrowerWrappersScript";

    ICollateralConfig immutable collateralConfig;
    ITroveManager immutable troveManager;
    IStabilityPool immutable stabilityPool;
    IPriceFeed immutable priceFeed;
    IERC20 immutable lusdToken;
    IERC20 immutable lqtyToken;

    constructor(
        address _borrowerOperationsAddress,
        address _collateralConfigAddress,
        address _troveManagerAddress,
        address _stabilityPoolAddress
    ) BorrowerOperationsScript(IBorrowerOperations(_borrowerOperationsAddress)) {
        checkContract(_collateralConfigAddress);
        ICollateralConfig collateralConfigCached = ICollateralConfig(_collateralConfigAddress);
        collateralConfig = collateralConfigCached;

        checkContract(_troveManagerAddress);
        ITroveManager troveManagerCached = ITroveManager(_troveManagerAddress);
        troveManager = troveManagerCached;

        checkContract(_stabilityPoolAddress);
        stabilityPool = IStabilityPool(_stabilityPoolAddress);

        IPriceFeed priceFeedCached = troveManagerCached.priceFeed();
        checkContract(address(priceFeedCached));
        priceFeed = priceFeedCached;

        address lusdTokenCached = address(troveManagerCached.lusdToken());
        checkContract(lusdTokenCached);
        lusdToken = IERC20(lusdTokenCached);

        address lqtyTokenCached = address(troveManagerCached.lqtyToken());
        checkContract(lqtyTokenCached);
        lqtyToken = IERC20(lqtyTokenCached);
    }

    function claimCollateralAndOpenTrove(
        address _collateral,
        uint _collAmount,
        uint _maxFee,
        uint _LUSDAmount,
        address _upperHint,
        address _lowerHint
    ) external {
        uint balanceBefore = IERC20(_collateral).balanceOf(address(this));

        // Claim collateral
        borrowerOperations.claimCollateral(_collateral);

        uint balanceAfter = IERC20(_collateral).balanceOf(address(this));

        // already checked in CollSurplusPool
        assert(balanceAfter > balanceBefore);

        uint totalCollateral = balanceAfter - balanceBefore + _collAmount;

        // Open trove with obtained collateral, plus collateral sent by user
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collAmount);
        IERC20(_collateral).safeIncreaseAllowance(address(borrowerOperations), totalCollateral);
        borrowerOperations.openTrove(
            _collateral,
            totalCollateral,
            _maxFee,
            _LUSDAmount,
            _upperHint,
            _lowerHint
        );
    }

    function _getNetLUSDAmount(address _collateral, uint _collAmount) internal returns (uint) {
        uint price = priceFeed.fetchPrice(_collateral);
        uint ICR = troveManager.getCurrentICR(address(this), _collateral, price);

        uint collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        uint LUSDAmount = (_getScaledCollAmount(_collAmount, collDecimals) * price) / ICR;
        uint borrowingRate = troveManager.getBorrowingRateWithDecay();
        uint netDebt = (LUSDAmount * LiquityMath.DECIMAL_PRECISION) /
            (LiquityMath.DECIMAL_PRECISION + borrowingRate);

        return netDebt;
    }

    function _requireUserHasTrove(address _depositor, address _collateral) internal view {
        require(
            troveManager.getTroveStatus(_depositor, _collateral) == 1,
            "BorrowerWrappersScript: caller must have an active trove"
        );
    }

    function _getScaledCollAmount(
        uint256 _collAmount,
        uint256 _collDecimals
    ) internal pure returns (uint256 scaledColl) {
        scaledColl = _collAmount;
        if (_collDecimals > LiquityMath.CR_CALCULATION_DECIMALS) {
            scaledColl = scaledColl / (10 ** (_collDecimals - LiquityMath.CR_CALCULATION_DECIMALS));
        } else if (_collDecimals < LiquityMath.CR_CALCULATION_DECIMALS) {
            scaledColl = scaledColl * (10 ** (LiquityMath.CR_CALCULATION_DECIMALS - _collDecimals));
        }
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./Interfaces/ILeverager.sol";
import "./Interfaces/IBorrowerOperations.sol";
import "./Interfaces/ICollateralConfig.sol";
import "./Interfaces/IPriceFeed.sol";
import "./Interfaces/ITroveManager.sol";
import "./Dependencies/ISwapper.sol";
import "./Dependencies/LiquityBase.sol";
import "./Dependencies/SafeMath.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/CheckContract.sol";
import "./Dependencies/SafeERC20.sol";

contract Leverager is LiquityBase, Ownable, CheckContract, ILeverager {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    bool public initialized = false;

    enum ExchangeType {
        VeloSolid,
        Bal,
        UniV3
    }

    struct ExchangeSettings {
        address veloRouter;
        address balVault;
        address uniV3Router;
    }

    ExchangeSettings public exchangeSettings;
    mapping(address => mapping(address => ExchangeType)) public exchangeForPair;
    ISwapper public swapper;

    /// @notice These represent the limits imposed on a regular caller of the Leverager contract.
    /// They can be fine-tuned by `owner` within hard limits specified in their respective setter functions.
    uint public maxLeverageIterations = 15;
    uint public minERNPrice = 0.99 ether;
    uint public maxERNPrice = 1.05 ether;
    uint public minSwapPercentOut = 0.99 ether;

    IBorrowerOperations public borrowerOperations;
    ICollateralConfig public collateralConfig;
    ITroveManager public troveManager;
    IERC20 public lusdToken;

    event BorrowerOperationsAddressChanged(address _borrowerOperationsAddress);
    event CollateralConfigAddressChanged(address _collateralConfigAddress);
    event TroveManagerAddressChanged(address _troveManagerAddress);
    event ActivePoolAddressChanged(address _activePoolAddress);
    event DefaultPoolAddressChanged(address _defaultPoolAddress);
    event PriceFeedAddressChanged(address _priceFeedAddress);
    event LUSDTokenAddressChanged(address _lusdTokenAddress);
    event SwapperAddressChanged(address _swapper);

    event MaxLeverageIterationsChanged(uint _iterations);
    event ExchangeForPairChanged(address indexed _tokenIn, address indexed _tokenOut, ExchangeType _exchange);
    event ExchangeSettingsChanged(ExchangeSettings _settings);
    event SlippageSettingsChanged(uint _minERNPrice, uint _maxERNPrice, uint _minSwapPercentOut);

    event LeveredTroveOpened(
        address indexed _borrower, address indexed _collateral, uint _totalDebt, uint _totalColl, uint _startingColl
    );

    function setAddresses(
        address _borrowerOperationsAddress,
        address _collateralConfigAddress,
        address _troveManagerAddress,
        address _activePoolAddress,
        address _defaultPoolAddress,
        address _priceFeedAddress,
        address _lusdTokenAddress,
        address _swapperAddress
    ) external onlyOwner {
        require(!initialized, "Can only initialize once");

        checkContract(_borrowerOperationsAddress);
        checkContract(_collateralConfigAddress);
        checkContract(_troveManagerAddress);
        checkContract(_activePoolAddress);
        checkContract(_defaultPoolAddress);
        checkContract(_priceFeedAddress);
        checkContract(_lusdTokenAddress);
        checkContract(_swapperAddress);

        borrowerOperations = IBorrowerOperations(_borrowerOperationsAddress);
        collateralConfig = ICollateralConfig(_collateralConfigAddress);
        troveManager = ITroveManager(_troveManagerAddress);
        activePool = IActivePool(_activePoolAddress);
        defaultPool = IDefaultPool(_defaultPoolAddress);
        priceFeed = IPriceFeed(_priceFeedAddress);
        lusdToken = IERC20(_lusdTokenAddress);
        swapper = ISwapper(_swapperAddress);

        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
        emit CollateralConfigAddressChanged(_collateralConfigAddress);
        emit TroveManagerAddressChanged(_troveManagerAddress);
        emit ActivePoolAddressChanged(_activePoolAddress);
        emit DefaultPoolAddressChanged(_defaultPoolAddress);
        emit PriceFeedAddressChanged(_priceFeedAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
        emit SwapperAddressChanged(_swapperAddress);

        initialized = true;
    }

    function setMaxLeverageIterations(uint _iterations) external onlyOwner {
        require(_iterations > 1 && _iterations <= 30, "Iterations outside allowable range");
        maxLeverageIterations = _iterations;
        emit MaxLeverageIterationsChanged(_iterations);
    }

    function setExchange(address _tokenIn, address _tokenOut, ExchangeType _exchange) external onlyOwner {
        exchangeForPair[_tokenIn][_tokenOut] = _exchange;
        emit ExchangeForPairChanged(_tokenIn, _tokenOut, _exchange);
    }

    function setExchangeSettings(ExchangeSettings memory _settings) external onlyOwner {
        checkContract(_settings.veloRouter);
        checkContract(_settings.balVault);
        checkContract(_settings.uniV3Router);
        exchangeSettings = _settings;
        emit ExchangeSettingsChanged(_settings);
    }

    function setSlippageSettings(uint _minERNPrice, uint _maxERNPrice, uint _minSwapPercentOut) external onlyOwner {
        require(
            _minERNPrice >= LiquityMath._getScaledCollAmount(98, 2)
                && _maxERNPrice <= LiquityMath._getScaledCollAmount(110, 2),
            "ERN price out of range 0.98-1.10"
        );
        require(_minSwapPercentOut >= LiquityMath._getScaledCollAmount(98, 2), "More than 2% slippage + fees");
        minERNPrice = _minERNPrice;
        maxERNPrice = _maxERNPrice;
        minSwapPercentOut = _minSwapPercentOut;
        emit SlippageSettingsChanged(_minERNPrice, _maxERNPrice, _minSwapPercentOut);
    }

    struct LocalVariables_leverToTargetCRWithNIterations {
        uint collPrice;
        uint collDecimals;
        uint lusdAmount;
        uint startingColl;
        uint totalColl;
        bool shouldOpenTrove;
    }

    /**
     * @notice Attempt to lever up with an exact number of looping iterations while maintaining a certain collateral ratio.
     * Trove must not be active. Will typically send a small amount of borrowed `lusdToken` back to caller.
     * @param _collateral The collateral for your given trove.
     * @param _targetCR The collateral ratio to maintain (in ether precision).
     * @param _n Exact number of iterations to run.
     * @param _collAmount Amount of `_collateral` to transfer to this contract and begin to loop with.
     * @param _maxFeePercentage Max percentage of the borrowing fee for each iteration.
     * @param _upperHint Address of borrower ideally just before caller in SortedTroves for given `_targetCR`.
     * @param _lowerHint Address of borrower ideally just after caller in SortedTroves for given `_targetCR`.
     * @param _ernPrice Current price of ERN (between `minERNPrice` and `maxERNPrice`) in ether precision.
     * @param _swapPercentOut Percentage (between `minSwapPercentOut` and 1 ether) of fair price to allow for each swap.
     */
    function leverToTargetCRWithNIterations(
        address _collateral,
        uint _targetCR,
        uint _n,
        uint _collAmount,
        uint _maxFeePercentage,
        address _upperHint,
        address _lowerHint,
        uint _ernPrice,
        uint _swapPercentOut
    ) external override {
        require(_n != 0, "Leverager: Zero iterations");
        require(_n <= maxLeverageIterations, "Leverager: Too many iterations");
        _requireERNPriceAndSwapPercentInRange(_ernPrice, _swapPercentOut);
        require(
            troveManager.getTroveStatus(msg.sender, _collateral) != uint(TroveStatus.active),
            "Leverager: Cannot lever up active trove"
        );

        LocalVariables_leverToTargetCRWithNIterations memory vars;
        vars.collPrice = priceFeed.fetchPrice(_collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        require(
            !_checkRecoveryMode(
                _collateral, vars.collPrice, collateralConfig.getCollateralCCR(_collateral), vars.collDecimals
            ),
            "Leverager: Cannot lever up during recovery mode"
        );

        vars.startingColl = _collAmount;
        vars.totalColl = _collAmount;
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _collAmount);

        vars.shouldOpenTrove = true;
        for (uint i; i < _n; ++i) {
            (_upperHint, _lowerHint) = _borrowLUSDWithCollAmount(
                Params__borrowLUSDWithCollAmount(
                    _collAmount,
                    _collateral,
                    vars.collDecimals,
                    vars.collPrice,
                    _targetCR,
                    _upperHint,
                    _lowerHint,
                    _maxFeePercentage,
                    vars.shouldOpenTrove
                )
            );
            vars.shouldOpenTrove = false;

            if (i != _n - 1) {
                vars.lusdAmount = lusdToken.balanceOf(address(this));
                MinAmountOutData memory minAmountOut = MinAmountOutData(
                    MinAmountOutKind.Absolute,
                    _getUnscaledCollAmount(
                        _findMinAmountOut(vars.collPrice, _ernPrice, vars.lusdAmount, _swapPercentOut),
                        vars.collDecimals
                    )
                );
                _collAmount = _swap(address(lusdToken), address(_collateral), vars.lusdAmount, minAmountOut);
                vars.totalColl = vars.totalColl.add(_collAmount);
            }
        }

        lusdToken.safeTransfer(msg.sender, lusdToken.balanceOf(address(this)));
        emit LeveredTroveOpened(
            msg.sender,
            _collateral,
            troveManager.getTroveDebt(msg.sender, _collateral),
            vars.totalColl,
            vars.startingColl
        );
    }

    struct LocalVariables_deleverAndCloseTrove {
        uint collPrice;
        uint collDecimals;
        uint collAmount;
        uint currentICR;
        address upperHint;
        address lowerHint;
        bool closedTrove;
    }

    /**
     * @notice Attempt to lever down with up to a little more than `maxLeverageIterations` iterations and close the trove.
     * Will typically send a fair amount of `_collateral` and `lusdToken` back to caller.
     * @param _collateral The collateral for your given trove.
     * @param _lusdAmount Amount of `lusdToken` to transfer to this contract and attempt to delever with.
     * @param _upperHint Address of borrower ideally just before caller in SortedTroves for given `_targetCR`.
     * @param _lowerHint Address of borrower ideally just after caller in SortedTroves for given `_targetCR`.
     * @param _ernPrice Current price of ERN (between `minERNPrice` and `maxERNPrice`) in ether precision.
     * @param _swapPercentOut Percentage (between `minSwapPercentOut` and 1 ether) of fair price to allow for each swap.
     */
    function deleverAndCloseTrove(
        address _collateral,
        uint _lusdAmount,
        address _upperHint,
        address _lowerHint,
        uint _ernPrice,
        uint _swapPercentOut
    ) external override {
        require(_lusdAmount != 0, "Leverager: Zero LUSD amount");
        _requireERNPriceAndSwapPercentInRange(_ernPrice, _swapPercentOut);

        LocalVariables_deleverAndCloseTrove memory vars;
        vars.collPrice = priceFeed.fetchPrice(_collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        vars.currentICR = troveManager.getCurrentICR(msg.sender, _collateral, vars.collPrice);

        lusdToken.safeTransferFrom(msg.sender, address(this), _lusdAmount);

        for (uint i; i < maxLeverageIterations + 3; ++i) {
            if (i != 0) {
                MinAmountOutData memory minAmountOut = MinAmountOutData(
                    MinAmountOutKind.Absolute,
                    _findMinAmountOut(
                        _ernPrice,
                        vars.collPrice,
                        LiquityMath._getScaledCollAmount(vars.collAmount, vars.collDecimals),
                        _swapPercentOut
                    )
                );
                _swap(address(_collateral), address(lusdToken), vars.collAmount, minAmountOut);
                _lusdAmount = lusdToken.balanceOf(address(this));
            }

            (vars.collAmount, vars.closedTrove, _upperHint, _lowerHint) = _delever(
                Params__delever(
                    _lusdAmount, _collateral, vars.collDecimals, vars.collPrice, vars.currentICR, _upperHint, _lowerHint
                )
            );

            if (vars.closedTrove) {
                IERC20(_collateral).safeTransfer(msg.sender, vars.collAmount);
                lusdToken.safeTransfer(msg.sender, lusdToken.balanceOf(address(this)));
                return;
            }
        }

        revert("Leverager: Failed to delever and close trove");
    }

    struct Params__borrowLUSDWithCollAmount {
        uint collAmount;
        address collateral;
        uint collDecimals;
        uint price;
        uint targetCR;
        address startingUpperHint;
        address startingLowerHint;
        uint maxFeePercentage;
        bool shouldOpenTrove;
    }

    function _borrowLUSDWithCollAmount(Params__borrowLUSDWithCollAmount memory params)
        internal
        returns (address newUpperHint, address newLowerHint)
    {
        uint scaledCollAmount = LiquityMath._getScaledCollAmount(params.collAmount, params.collDecimals);
        // CR = dollar value of coll / debt
        // CR * debt = dollar value of coll
        // CR * debt = coll amount * coll price
        // (coll amount * coll price) / CR = dollar value of debt
        uint newDebt = scaledCollAmount.mul(params.price).div(params.targetCR);
        if (params.shouldOpenTrove) {
            newDebt = newDebt.sub(LUSD_GAS_COMPENSATION);
        }
        uint newDebtMinusFee = newDebt.sub(troveManager.getBorrowingFeeWithDecay(newDebt));

        IERC20(params.collateral).safeIncreaseAllowance(address(borrowerOperations), params.collAmount);
        if (params.shouldOpenTrove) {
            (newUpperHint, newLowerHint) = borrowerOperations.openTroveFor(
                msg.sender,
                params.collateral,
                params.collAmount,
                params.maxFeePercentage,
                newDebtMinusFee,
                params.startingUpperHint,
                params.startingLowerHint
            );
        } else {
            (newUpperHint, newLowerHint) = borrowerOperations.adjustTroveFor(
                IBorrowerOperations.Params_adjustTroveFor(
                    msg.sender,
                    params.collateral,
                    params.maxFeePercentage,
                    params.collAmount,
                    0,
                    newDebtMinusFee,
                    true,
                    params.startingUpperHint,
                    params.startingLowerHint
                )
            );
        }
    }

    struct Params__delever {
        uint lusdAmount;
        address collateral;
        uint collDecimals;
        uint price;
        uint targetCR;
        address startingUpperHint;
        address startingLowerHint;
    }

    function _delever(Params__delever memory params)
        internal
        returns (uint collAmountWithdrawn, bool closedTrove, address newUpperHint, address newLowerHint)
    {
        uint debt = _getNetDebt(troveManager.getTroveDebt(msg.sender, params.collateral));
        if (debt < params.lusdAmount) {
            borrowerOperations.closeTroveFor(msg.sender, params.collateral);
            collAmountWithdrawn = IERC20(params.collateral).balanceOf(address(this));
            return (collAmountWithdrawn, true, address(0), address(0));
        }

        uint debtAfterRepayment = debt - params.lusdAmount;
        if (debtAfterRepayment < MIN_NET_DEBT) {
            params.lusdAmount -= MIN_NET_DEBT - debtAfterRepayment;
            debtAfterRepayment = MIN_NET_DEBT;
        }

        uint troveCollValue = troveManager.getTroveColl(msg.sender, params.collateral);
        troveCollValue = LiquityMath._getScaledCollAmount(troveCollValue, params.collDecimals).mul(params.price);
        // To find x (dollar value of collAmountWithdrawn)
        // (collAmountInTrove * collPrice / 1 ether) - x = debtAfterRepayment * targetCR
        // x = (collAmountInTrove * collPrice / 1 ether) - (debtAfterRepayment * targetCR)
        // We then divide by price to get actual collAmountWithdrawn (not denominated in dollars)
        collAmountWithdrawn =
            troveCollValue.sub(debtAfterRepayment.add(LUSD_GAS_COMPENSATION).mul(params.targetCR)).div(params.price);
        collAmountWithdrawn = _getUnscaledCollAmount(collAmountWithdrawn, params.collDecimals);

        (newUpperHint, newLowerHint) = borrowerOperations.adjustTroveFor(
            IBorrowerOperations.Params_adjustTroveFor(
                msg.sender,
                params.collateral,
                0,
                0,
                collAmountWithdrawn,
                params.lusdAmount,
                false,
                params.startingUpperHint,
                params.startingLowerHint
            )
        );
    }

    function _swap(address _tokenIn, address _tokenOut, uint _amountIn, MinAmountOutData memory _data)
        internal
        returns (uint amountOut)
    {
        IERC20(_tokenIn).safeIncreaseAllowance(address(swapper), _amountIn);
        ExchangeType exchange = exchangeForPair[_tokenIn][_tokenOut];
        if (exchange == ExchangeType.Bal) {
            amountOut = swapper.swapBal(_tokenIn, _tokenOut, _amountIn, _data, exchangeSettings.balVault);
        } else if (exchange == ExchangeType.VeloSolid) {
            amountOut = swapper.swapVelo(_tokenIn, _tokenOut, _amountIn, _data, exchangeSettings.veloRouter);
        } else if (exchange == ExchangeType.UniV3) {
            amountOut = swapper.swapUniV3(_tokenIn, _tokenOut, _amountIn, _data, exchangeSettings.uniV3Router);
        } else {
            revert("Leverager: Invalid ExchangeType");
        }

        require(amountOut >= _data.absoluteOrBPSValue, "Leverager: Swap failed");
    }

    function _findMinAmountOut(uint _priceOut, uint _priceIn, uint _amountIn, uint _minPercentOut)
        internal
        pure
        returns (uint)
    {
        // _amountIn * _priceIn * (_minPercentOut / DECIMAL_PRECISISION) = _amountOut * _priceOut
        // ^ (dollar value in)    ^ (account for slippage and fees)        ^ (dollar value out)
        // solving for _amountOut
        // _amountOut = _amountIn * _priceIn * (_minPercentOut / DECIMAL_PRECISION) / _priceOut
        return _amountIn.mul(_priceIn).mul(_minPercentOut).div(_priceOut).div(LiquityMath.DECIMAL_PRECISION);
    }

    function _requireERNPriceAndSwapPercentInRange(uint _ernPrice, uint _swapPercentOut) internal view {
        require(_ernPrice >= minERNPrice && _ernPrice <= maxERNPrice, "Leverager: ERN price out of range");
        require(_swapPercentOut >= minSwapPercentOut, "Leverager: Too much slippage");
        require(_swapPercentOut <= LiquityMath.DECIMAL_PRECISION, "Leverager: Negative slippage");
    }

    function _getUnscaledCollAmount(uint _collAmount, uint _collDecimals) internal pure returns (uint unscaledColl) {
        unscaledColl = _collAmount;
        if (_collDecimals > LiquityMath.CR_CALCULATION_DECIMALS) {
            unscaledColl = unscaledColl.mul(10 ** (_collDecimals - LiquityMath.CR_CALCULATION_DECIMALS));
        } else if (_collDecimals < LiquityMath.CR_CALCULATION_DECIMALS) {
            unscaledColl = unscaledColl.div(10 ** (LiquityMath.CR_CALCULATION_DECIMALS - _collDecimals));
        }
    }
}

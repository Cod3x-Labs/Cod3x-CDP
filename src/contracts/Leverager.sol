// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

import {ILeverager} from "./Interfaces/ILeverager.sol";
import {IBorrowerOperations} from "./Interfaces/IBorrowerOperations.sol";
import {ICollateralConfig} from "./Interfaces/ICollateralConfig.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {ITroveManager, TroveStatus} from "./Interfaces/ITroveManager.sol";
import {ISwapper, MinAmountOutData, MinAmountOutKind} from "./Dependencies/ISwapper.sol";
import {LiquityBase, IActivePool, IDefaultPool, LiquityMath} from "./Dependencies/LiquityBase.sol";
import {Ownable} from "./Dependencies/Ownable.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Leverager is LiquityBase, Ownable, CheckContract, ILeverager {
    using SafeERC20 for IERC20;

    bool public initialized = false;

    enum ExchangeType {
        None,
        VeloSolid,
        Bal,
        UniV2,
        UniV3
    }

    struct Exchange {
        ExchangeType _type;
        address router;
    }

    struct SwapPath {
        address[] tokens;
        Exchange[] exchanges;
    }

    mapping(address => mapping(address => SwapPath)) private _swapPaths;
    ISwapper public swapper;

    /// @notice These variables represent the limits imposed on a regular caller of the Leverager contract.
    /// They can be fine-tuned by `owner` within hard limits specified by the constants.
    uint public constant ABS_MAX_ITERATIONS = 30;
    uint public constant ABS_MIN_ERN_PRICE = 0.98 ether;
    uint public constant ABS_MAX_ERN_PRICE = 1.10 ether;
    uint public constant ABS_MIN_SWAP_PERC_OUT = 0.98 ether;
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
    event SwapPathChanged(
        address indexed _tokenIn,
        address indexed _tokenOut,
        SwapPath _path
    );
    event SlippageSettingsChanged(uint _minERNPrice, uint _maxERNPrice, uint _minSwapPercentOut);

    event LeveredTroveOpened(
        address indexed _borrower,
        address indexed _collateral,
        uint _totalDebt,
        uint _totalColl,
        uint _startingColl
    );

    error AlreadyInitialized();
    error InvalidIterations(uint _iterations);
    error SwapPathLengthMismatch(uint _exchangesLength, uint _tokensLength);
    error PathDoesNotMatchTokens();
    error InvalidIOTokens(address _tokenIn, address _tokenOut);
    error ERNPriceOutOfRange();
    error TooLowSwapPercentOut(uint _minSwapPercentOut, uint _absMinSwapPercentOut);
    error ZeroIterations();
    error TooManyIterations(uint _iterations, uint _maxIterations);
    error AttemptToLeverActiveTrove();
    error AttemptToLeverDuringRecovery();
    error ZeroLUSDAmount();
    error DeleverAndCloseFailed();
    error InvalidExchangeType(ExchangeType _type);
    error AmountOutBelowMin(uint _amountOut, uint _min);
    error TooMuchSlippage(uint _swapPercentOut, uint _minSwapPercentOut);
    error NegativeSlippage(uint _swapPercentOut);

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
        if (initialized) revert AlreadyInitialized();

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
        if (_iterations <= 1 || _iterations > 30) revert InvalidIterations(_iterations);
        maxLeverageIterations = _iterations;
        emit MaxLeverageIterationsChanged(_iterations);
    }

    function setSwapPath(
        address _tokenIn,
        address _tokenOut,
        SwapPath memory _path
    ) external onlyOwner {
        if (_path.exchanges.length != _path.tokens.length - 1) {
            revert SwapPathLengthMismatch(_path.exchanges.length, _path.tokens.length);
        }

        // only allow lusdToken to collateral or vice versa
        if (_path.tokens[0] != _tokenIn || _path.tokens[_path.tokens.length - 1] != _tokenOut) {
            revert PathDoesNotMatchTokens();
        }
        if (_tokenIn == address(lusdToken)) {
            if (!collateralConfig.isCollateralAllowed(_tokenOut)) revert InvalidIOTokens(_tokenIn, _tokenOut);
        } else if (_tokenOut == address(lusdToken)) {
            if (!collateralConfig.isCollateralAllowed(_tokenIn)) revert InvalidIOTokens(_tokenIn, _tokenOut);
        } else {
            revert InvalidIOTokens(_tokenIn, _tokenOut);
        }

        for (uint i; i < _path.tokens.length; ++i) {
            checkContract(_path.tokens[i]);
            if (i != _path.exchanges.length) {
                checkContract(_path.exchanges[i].router);
            }
        }

        _swapPaths[_tokenIn][_tokenOut] = _path;
        emit SwapPathChanged(_tokenIn, _tokenOut, _path);
    }

    function setSlippageSettings(
        uint _minERNPrice,
        uint _maxERNPrice,
        uint _minSwapPercentOut
    ) external onlyOwner {
        if (_minERNPrice < ABS_MIN_ERN_PRICE || _maxERNPrice > ABS_MAX_ERN_PRICE) {
            revert ERNPriceOutOfRange();
        }
        if(_minSwapPercentOut < ABS_MIN_SWAP_PERC_OUT) {
            revert TooLowSwapPercentOut(_minSwapPercentOut, ABS_MIN_SWAP_PERC_OUT);
        }
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
        if (_n == 0) revert ZeroIterations();
        if (_n > maxLeverageIterations) revert TooManyIterations(_n, maxLeverageIterations);
        _requireERNPriceAndSwapPercentInRange(_ernPrice, _swapPercentOut);
        if (troveManager.getTroveStatus(msg.sender, _collateral) == uint(TroveStatus.active)) {
            revert AttemptToLeverActiveTrove();
        }

        LocalVariables_leverToTargetCRWithNIterations memory vars;
        vars.collPrice = priceFeed.fetchPrice(_collateral);
        vars.collDecimals = collateralConfig.getCollateralDecimals(_collateral);
        if (_checkRecoveryMode(
            _collateral,
            vars.collPrice,
            collateralConfig.getCollateralCCR(_collateral),
            vars.collDecimals
        )) {
            revert AttemptToLeverDuringRecovery();
        }

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
                        _findMinAmountOut(
                            vars.collPrice,
                            _ernPrice,
                            vars.lusdAmount,
                            _swapPercentOut
                        ),
                        vars.collDecimals
                    )
                );
                _collAmount = _swap(
                    address(lusdToken),
                    address(_collateral),
                    vars.lusdAmount,
                    minAmountOut
                );
                vars.totalColl = vars.totalColl + _collAmount;
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
        if (_lusdAmount == 0) revert ZeroLUSDAmount();
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
                    _lusdAmount,
                    _collateral,
                    vars.collDecimals,
                    vars.collPrice,
                    vars.currentICR,
                    _upperHint,
                    _lowerHint
                )
            );

            if (vars.closedTrove) {
                IERC20(_collateral).safeTransfer(msg.sender, vars.collAmount);
                lusdToken.safeTransfer(msg.sender, lusdToken.balanceOf(address(this)));
                return;
            }
        }

        revert DeleverAndCloseFailed();
    }

    function swapPath(address _tokenIn, address _tokenOut) external view returns (SwapPath memory) {
        return _swapPaths[_tokenIn][_tokenOut];
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

    function _borrowLUSDWithCollAmount(
        Params__borrowLUSDWithCollAmount memory params
    ) internal returns (address newUpperHint, address newLowerHint) {
        uint scaledCollAmount = LiquityMath._getScaledCollAmount(
            params.collAmount,
            params.collDecimals
        );
        // CR = dollar value of coll / debt
        // CR * debt = dollar value of coll
        // CR * debt = coll amount * coll price
        // (coll amount * coll price) / CR = dollar value of debt
        uint newDebt = (scaledCollAmount * params.price) / params.targetCR;
        if (params.shouldOpenTrove) {
            newDebt = newDebt - LUSD_GAS_COMPENSATION;
        }
        uint newDebtMinusFee = newDebt - troveManager.getBorrowingFeeWithDecay(newDebt);

        IERC20(params.collateral).safeIncreaseAllowance(
            address(borrowerOperations),
            params.collAmount
        );
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

    function _delever(
        Params__delever memory params
    )
        internal
        returns (
            uint collAmountWithdrawn,
            bool closedTrove,
            address newUpperHint,
            address newLowerHint
        )
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
        troveCollValue =
            LiquityMath._getScaledCollAmount(troveCollValue, params.collDecimals) *
            params.price;
        // To find x (dollar value of collAmountWithdrawn)
        // (collAmountInTrove * collPrice / 1 ether) - x = debtAfterRepayment * targetCR
        // x = (collAmountInTrove * collPrice / 1 ether) - (debtAfterRepayment * targetCR)
        // We then divide by price to get actual collAmountWithdrawn (not denominated in dollars)
        collAmountWithdrawn =
            (troveCollValue - ((debtAfterRepayment + LUSD_GAS_COMPENSATION) * params.targetCR)) /
            params.price;
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

    function _swap(
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        MinAmountOutData memory _data
    ) internal returns (uint amountOut) {
        SwapPath memory path = _swapPaths[_tokenIn][_tokenOut];
        uint lastIteration = path.exchanges.length - 1;
        for (uint i; i < path.exchanges.length; ++i) {
            MinAmountOutData memory data;
            if (i == lastIteration) {
                data = _data;
            } else {
                data = MinAmountOutData(MinAmountOutKind.Absolute, 1);
            }

            Exchange memory exchange = path.exchanges[i];
            IERC20(path.tokens[i]).safeIncreaseAllowance(address(swapper), _amountIn);
            if (exchange._type == ExchangeType.Bal) {
                amountOut = swapper.swapBal(
                    path.tokens[i],
                    path.tokens[i + 1],
                    _amountIn,
                    data,
                    exchange.router,
                    block.timestamp,
                    false
                );
            } else if (exchange._type == ExchangeType.VeloSolid) {
                amountOut = swapper.swapVelo(
                    path.tokens[i],
                    path.tokens[i + 1],
                    _amountIn,
                    data,
                    exchange.router,
                    block.timestamp,
                    false
                );
            } else if (exchange._type == ExchangeType.UniV2) {
                amountOut = swapper.swapUniV2(
                    path.tokens[i],
                    path.tokens[i + 1],
                    _amountIn,
                    data,
                    exchange.router,
                    block.timestamp,
                    false
                );
            } else if (exchange._type == ExchangeType.UniV3) {
                amountOut = swapper.swapUniV3(
                    path.tokens[i],
                    path.tokens[i + 1],
                    _amountIn,
                    data,
                    exchange.router,
                    block.timestamp,
                    false
                );
            } else {
                revert InvalidExchangeType(exchange._type);
            }
            _amountIn = amountOut;
        }

        if (amountOut < _data.absoluteOrBPSValue) {
            revert AmountOutBelowMin(amountOut, _data.absoluteOrBPSValue);
        }
    }

    function _findMinAmountOut(
        uint _priceOut,
        uint _priceIn,
        uint _amountIn,
        uint _minPercentOut
    ) internal pure returns (uint) {
        // _amountIn * _priceIn * (_minPercentOut / DECIMAL_PRECISISION) = _amountOut * _priceOut
        // ^ (dollar value in)    ^ (account for slippage and fees)        ^ (dollar value out)
        // solving for _amountOut
        // _amountOut = _amountIn * _priceIn * (_minPercentOut / DECIMAL_PRECISION) / _priceOut
        return (_amountIn * _priceIn * _minPercentOut) / _priceOut / LiquityMath.DECIMAL_PRECISION;
    }

    function _requireERNPriceAndSwapPercentInRange(
        uint _ernPrice,
        uint _swapPercentOut
    ) internal view {
        if (_ernPrice < minERNPrice || _ernPrice > maxERNPrice) {
            revert ERNPriceOutOfRange();
        }
        if (_swapPercentOut < minSwapPercentOut) {
            revert TooMuchSlippage(_swapPercentOut, minSwapPercentOut);
        }
        if (_swapPercentOut > LiquityMath.DECIMAL_PRECISION) {
            revert NegativeSlippage(_swapPercentOut);
        }
    }

    function _getUnscaledCollAmount(
        uint _collAmount,
        uint _collDecimals
    ) internal pure returns (uint unscaledColl) {
        unscaledColl = _collAmount;
        if (_collDecimals > LiquityMath.CR_CALCULATION_DECIMALS) {
            unscaledColl =
                unscaledColl *
                10 ** (_collDecimals - LiquityMath.CR_CALCULATION_DECIMALS);
        } else if (_collDecimals < LiquityMath.CR_CALCULATION_DECIMALS) {
            unscaledColl =
                unscaledColl /
                10 ** (LiquityMath.CR_CALCULATION_DECIMALS - _collDecimals);
        }
    }
}

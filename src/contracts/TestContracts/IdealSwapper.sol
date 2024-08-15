// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Test.sol";
import "../Dependencies/ISwapper.sol";
import {LiquityMath} from "../Dependencies/LiquityMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Interfaces/ICollateralConfig.sol";
import "../Interfaces/IPriceFeed.sol";

contract IdealSwapper is ISwapper, Test {
    using SafeERC20 for IERC20;

    ICollateralConfig collateralConfig;
    IPriceFeed priceFeed;
    address ern;

    constructor(ICollateralConfig _collateralConfig, IPriceFeed _priceFeed, address _ern) {
        collateralConfig = _collateralConfig;
        priceFeed = _priceFeed;
        ern = _ern;
    }

    function swapBal(
        address _from,
        address _to,
        uint _amount,
        MinAmountOutData memory, // _minAmountOutData
        address, // _router
        uint, // _deadline
        bool // _tryCatchActive
    ) external override returns (uint) {
        return _swap(_from, _to, _amount);
    }

    function swapVelo(
        address _from,
        address _to,
        uint _amount,
        MinAmountOutData memory, // _minAmountOutData
        address, // _router
        uint, // _deadline
        bool // _tryCatchActive
    ) external override returns (uint) {
        return _swap(_from, _to, _amount);
    }

    function swapUniV2(
        address _from,
        address _to,
        uint _amount,
        MinAmountOutData memory, // _minAmountOutData
        address, // _router
        uint, // _deadline
        bool // _tryCatchActive
    ) external override returns (uint) {
        return _swap(_from, _to, _amount);
    }

    function swapUniV3(
        address _from,
        address _to,
        uint _amount,
        MinAmountOutData memory, // _minAmountOutData
        address, // _router
        uint, // _deadline
        bool // _tryCatchActive
    ) external override returns (uint) {
        return _swap(_from, _to, _amount);
    }

    /// @dev Perform no-slippage mint/burn swap assuming ERN = $1
    function _swap(address _from, address _to, uint _amount) internal returns (uint amountOut) {
        address coll = (_from == ern ? _to : _from);
        uint collPrice = priceFeed.fetchPrice(coll);
        uint collDecimals = collateralConfig.getCollateralDecimals(coll);
        if (_from == ern) {
            IERC20(ern).safeTransferFrom(msg.sender, address(1), _amount);
            amountOut = _amount * 10 ** collDecimals / collPrice;

            deal(coll, msg.sender, IERC20(coll).balanceOf(msg.sender) + amountOut);
        } else {
            IERC20(coll).safeTransferFrom(msg.sender, address(1), _amount);
            amountOut = LiquityMath._getScaledCollAmount(_amount, collDecimals) * collPrice / 1 ether;

            deal(ern, msg.sender, IERC20(ern).balanceOf(msg.sender) + amountOut);
        }
    }
}

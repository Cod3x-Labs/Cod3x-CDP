// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

enum MinAmountOutKind {
    Absolute,
    ChainlinkBased
}

struct MinAmountOutData {
    MinAmountOutKind kind;
    uint256 absoluteOrBPSValue; // for type "ChainlinkBased", value must be in BPS
}

struct UniV3SwapData {
    address[] path;
    uint24[] fees;
}

interface ISwapper {
    function swapUniV2(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router,
        uint256 _deadline,
        bool _tryCatchActive
    ) external returns (uint256);

    function swapBal(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _vault,
        uint256 _deadline,
        bool _tryCatchActive
    ) external returns (uint256);

    function swapVelo(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router,
        uint256 _deadline,
        bool _tryCatchActive
    ) external returns (uint256);

    function swapUniV3(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router,
        uint256 _deadline,
        bool _tryCatchActive
    ) external returns (uint256);
}

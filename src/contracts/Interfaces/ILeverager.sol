// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

interface ILeverager {
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
    ) external;

    function deleverAndCloseTrove(
        address _collateral,
        uint _lusdAmount,
        address _upperHint,
        address _lowerHint,
        uint _ernPrice,
        uint _swapPercentOut
    ) external;
}

// SPDX-License-Identifier: BUSL1.1

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./IVeloRouter.sol";

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
    function uniV2SwapPaths(address _from, address _to, address _router, uint256 _index) external returns (address);

    function balSwapPoolIDs(address _from, address _to, address _vault) external returns (bytes32);

    function veloSwapPaths(address _from, address _to, address _router, uint256 _index)
        external
        returns (IVeloRouter.Route memory route);

    function uniV3SwapPaths(address _from, address _to, address _router) external view returns (UniV3SwapData memory);

    function aggregatorData(address _token) external returns (address, uint256);

    function updateUniV2SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external;

    function updateBalSwapPoolID(address _tokenIn, address _tokenOut, address _vault, bytes32 _poolID) external;

    function updateVeloSwapPath(
        address _tokenIn,
        address _tokenOut,
        address _router,
        IVeloRouter.Route[] calldata _path
    ) external;

    function updateUniV3SwapPath(
        address _tokenIn,
        address _tokenOut,
        address _router,
        UniV3SwapData calldata _swapPathAndFees
    ) external;

    function updateTokenAggregator(address _token, address _aggregator, uint256 _timeout) external;

    function swapUniV2(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external returns (uint256);

    function swapBal(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _vault
    ) external returns (uint256);

    function swapVelo(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external returns (uint256);

    function swapUniV3(
        address _from,
        address _to,
        uint256 _amount,
        MinAmountOutData memory _minAmountOutData,
        address _router
    ) external returns (uint256);

    /**
     * Returns asset price from the Chainlink aggregator with 18 decimal precision.
     * Reverts if:
     * - asset doesn't have an aggregator registered
     * - asset's aggregator is considered broken (doesn't have valid historical response)
     * - asset's aggregator is considered frozen (last response exceeds asset's allowed timeout)
     */
    function getChainlinkPriceTargetDigits(address _token) external view returns (uint256 price);
}

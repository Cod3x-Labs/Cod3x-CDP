// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC4626Mock is ERC4626 {
    uint256 private assetsPerShare;
    bool private assetPerShareOverriden = false;

    constructor(
        address asset,
        string memory name,
        string memory symbol
    ) ERC4626(IERC20(asset)) ERC20(name, symbol) {}

    function setAssetsPerShare(uint8 assetsPerShare_) external {
        assetsPerShare = assetsPerShare_ * 10 ** decimals();
        assetPerShareOverriden = true;
    }

    function resetAssetsPerShare() external {
        assetPerShareOverriden = false;
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return
            assetPerShareOverriden ? assetsPerShare : _convertToAssets(shares, Math.Rounding.Floor);
    }
}

// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

interface ICollateralConfig {
    function getAllowedCollaterals() external view returns (address[] memory);
    function getCollateralCCR(address _collateral) external view returns (uint256);
    function getCollateralDecimals(address _collateral) external view returns (uint256);
    function getCollateralMCR(address _collateral) external view returns (uint256);
    function getCollateralDebtLimit(address _collateral) external view returns (uint256);
    function isCollateralAllowed(address _collateral) external view returns (bool);
    function getCollateralChainlinkTimeout(address _collateral) external view returns (uint256);
    function getCollateralTellorTimeout(address _collateral) external view returns (uint256);
}

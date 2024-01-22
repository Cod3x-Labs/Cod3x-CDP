// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.11;

import "./Dependencies/CheckContract.sol";
import "./Dependencies/Ownable.sol";
import "./Dependencies/SafeERC20.sol";
import "./Interfaces/ICollateralConfig.sol";
import "./Interfaces/IActivePool.sol";
import "./Interfaces/IPriceFeed.sol";

/**
 * Houses whitelist of allowed collaterals (ERC20s) for the entire system. Also provides access to collateral-specific
 * properties such as decimals, MCR, and CCR. Allowed collaterals and their properties may only be set once
 * during initialization after which they are immutable.
 */
contract CollateralConfig is ICollateralConfig, CheckContract, Ownable {
    using SafeERC20 for IERC20;

    bool public initialized = false;

    // Smallest allowed value for the minimum collateral ratio for individual troves in each market (collateral)
    uint256 constant public MIN_ALLOWED_MCR = 1.005 ether; // 100.5%

    // Smallest allowed value for Critical system collateral ratio.
    // If a market's (collateral's) total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    uint256 constant public MIN_ALLOWED_CCR = 1.01 ether; // 101%

    struct Config {
        bool allowed;
        uint256 decimals;
        uint256 MCR;
        uint256 CCR;
        uint256 debtLimit;
        uint256 chainlinkTimeout;
        uint256 tellorTimeout;
    }

    address[] public collaterals; // for returning entire list of allowed collaterals
    mapping (address => Config) public collateralConfig; // for O(1) checking of collateral's validity and properties

    IActivePool public activePool;
    IPriceFeed public priceFeed;

    event CollateralWhitelisted(
        address _collateral,
        uint256 _decimals,
        uint256 _MCR,
        uint256 _CCR,
        uint256 _debtLimit,
        uint256 _chainlinkTimeout,
        uint256 _tellorTimeout
    );
    event CollateralRatiosUpdated(address _collateral, uint256 _MCR, uint256 _CCR);
    event CollateralDebtLimitUpdated(address _collateral, uint256 _debtLimit);
    event CollateralOracleTimeoutsUpdated(address _collateral, uint256 _chainlinkTimeout, uint256 _tellorTimeout);

    /**
     * @notice One-time owner-only initializer.
     * @param _collaterals Ordered list of ERC20 tokens that will be allowed as collateral throughout the system.
     * @param _MCRs Ordered list of minimum collateralization ratio (MCR) for each of the collaterals.
     * @param _CCRs Ordered list of critical collateralization ratio (CCR) for each of the collaterals.
     * @param _debtLimits Ordered list of debt limits (prevents minting after being reached) for each of the collaterals.
     * @param _chainlinkTimeouts Ordered list of Chainlink timeouts (number of seconds after which price is considered
     * stale) for each of the collaterals.
     */
    function initialize(
        address[] calldata _collaterals,
        uint256[] calldata _MCRs,
        uint256[] calldata _CCRs,
        uint256[] calldata _debtLimits,
        uint256[] calldata _chainlinkTimeouts,
        uint256[] calldata _tellorTimeouts,
        address _activePool,
        address _priceFeed
    ) external onlyOwner {
        require(!initialized, "Can only initialize once");
        require(_collaterals.length != 0, "At least one collateral required");
        require(_MCRs.length == _collaterals.length, "Array lengths must match");
        require(_CCRs.length == _collaterals.length, "Array lenghts must match");
        require(_debtLimits.length == _collaterals.length, "Array lengths must match");
        require(_chainlinkTimeouts.length == _collaterals.length, "Array lengths must match");
        require(_tellorTimeouts.length == _collaterals.length, "Array lengths must match");

        for(uint256 i = 0; i < _collaterals.length; i++) {
            _addNewCollateral(_collaterals[i], _MCRs[i], _CCRs[i], _debtLimits[i], _chainlinkTimeouts[i], _tellorTimeouts[i]);
        }

        checkContract(_activePool);
        checkContract(_priceFeed);
        activePool = IActivePool(_activePool);
        priceFeed = IPriceFeed(_priceFeed);

        initialized = true;
    }

    function addNewCollateral(
        address _collateral,
        uint256 _MCR,
        uint256 _CCR,
        uint256 _debtLimit,
        uint256 _chainlinkTimeout,
        uint256 _tellorTimeout,
        address _vault,
        address _chainlinkAggregator,
        bytes32 _tellorQueryId
    ) external onlyOwner {
        _addNewCollateral(_collateral, _MCR, _CCR, _debtLimit, _chainlinkTimeout, _tellorTimeout);
        activePool.setYieldGenerator(_collateral, _vault);
        priceFeed.updateChainlinkAggregator(_collateral, _chainlinkAggregator);
        priceFeed.updateTellorQueryID(_collateral, _tellorQueryId);
    }

    function _addNewCollateral(
        address _collateral,
        uint256 _MCR,
        uint256 _CCR,
        uint256 _debtLimit,
        uint256 _chainlinkTimeout,
        uint256 _tellorTimeout
    ) internal {
        require(_collateral != address(0), "cannot be 0 address");
        require(_MCR >= MIN_ALLOWED_MCR, "MCR below allowed minimum");
        require(_CCR >= MIN_ALLOWED_CCR, "CCR below allowed minimum");
        require(_chainlinkTimeout != 0, "No Chainlink timeout specified");
        require(_tellorTimeout > 20 minutes, "Tellor timeout too low");
        Config storage config = collateralConfig[_collateral];
        require(!config.allowed, "collateral already allowed");

        checkContract(_collateral);
        collaterals.push(_collateral);

        config.allowed = true;
        config.debtLimit = _debtLimit;
        config.MCR = _MCR;
        config.CCR = _CCR;
        uint256 decimals = IERC20(_collateral).decimals();
        config.decimals = decimals;
        config.chainlinkTimeout = _chainlinkTimeout;
        config.tellorTimeout = _tellorTimeout;

        emit CollateralWhitelisted(_collateral, decimals, _MCR, _CCR, _debtLimit, _chainlinkTimeout, _tellorTimeout);
    }

    function updateCollateralDebtLimit(
        address _collateral,
        uint256 _debtLimit
    ) external onlyOwner checkCollateral(_collateral) {
        Config storage config = collateralConfig[_collateral];
        config.debtLimit = _debtLimit;

        emit CollateralDebtLimitUpdated(_collateral, _debtLimit);
    }

    // Admin function to lower the collateralization requirements for a particular collateral.
    // Can only lower, not increase.
    //
    // !!!PLEASE USE EXTREME CARE AND CAUTION. THIS IS IRREVERSIBLE!!!
    //
    // You probably don't want to do this unless a specific asset has proved itself through tough times.
    // Doing this irresponsibly can permanently harm the protocol.
    function updateCollateralRatios(
        address _collateral,
        uint256 _MCR,
        uint256 _CCR
    ) external onlyOwner checkCollateral(_collateral) {
        Config storage config = collateralConfig[_collateral];
        require(_MCR <= config.MCR, "Can only walk down the MCR");
        require(_CCR <= config.CCR, "Can only walk down the CCR");

        require(_MCR >= MIN_ALLOWED_MCR, "MCR below allowed minimum");
        config.MCR = _MCR;

        require(_CCR >= MIN_ALLOWED_CCR, "CCR below allowed minimum");
        config.CCR = _CCR;
        emit CollateralRatiosUpdated(_collateral, _MCR, _CCR);
    }

    function updateCollateralOracleTimeouts(
        address _collateral,
        uint256 _chainlinkTimeout,
        uint256 _tellorTimeout
    ) external onlyOwner checkCollateral(_collateral) {
        require(_chainlinkTimeout != 0, "No Chainlink timeout specified");
        require(_tellorTimeout > 20 minutes, "Tellor timeout too low");
        Config storage config = collateralConfig[_collateral];
        config.chainlinkTimeout = _chainlinkTimeout;
        config.tellorTimeout = _tellorTimeout;
        emit CollateralOracleTimeoutsUpdated(_collateral, _chainlinkTimeout, _tellorTimeout);
    }

    function getAllowedCollaterals() external override view returns (address[] memory) {
        return collaterals;
    }

    function isCollateralAllowed(address _collateral) external override view returns (bool) {
        return collateralConfig[_collateral].allowed;
    }

    function getCollateralDecimals(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].decimals;
    }

    function getCollateralMCR(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].MCR;
    }

    function getCollateralCCR(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].CCR;
    }

    function getCollateralDebtLimit(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].debtLimit;
    }

    function getCollateralChainlinkTimeout(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].chainlinkTimeout;
    }

    function getCollateralTellorTimeout(
        address _collateral
    ) external override view checkCollateral(_collateral) returns (uint256) {
        return collateralConfig[_collateral].tellorTimeout;
    }

    modifier checkCollateral(address _collateral) {
        require(collateralConfig[_collateral].allowed, "Invalid collateral address");
        _;
    }
}

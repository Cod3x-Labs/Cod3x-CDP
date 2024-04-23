// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ICollateralConfig} from "./Interfaces/ICollateralConfig.sol";
import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {ITellorCaller} from "./Interfaces/ITellorCaller.sol";
import {AggregatorV3Interface} from "./Dependencies/AggregatorV3Interface.sol";
import {SafeMath} from "./Dependencies/SafeMath.sol";
import {Ownable} from "./Dependencies/Ownable.sol";
import {CheckContract} from "./Dependencies/CheckContract.sol";
import {BaseMath} from "./Dependencies/BaseMath.sol";
import {LiquityMath} from "./Dependencies/LiquityMath.sol";

/*
 * The PriceFeed uses Chainlink-like as primary oracle, and Tellor as fallback. It contains logic for
 * switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
 * Chainlink oracle.
 */
contract PriceFeed is Ownable, CheckContract, BaseMath, IPriceFeed {
    using SafeMath for uint256;

    string public constant NAME = "PriceFeed";

    bool public initialized = false;

    mapping(address => AggregatorV3Interface) public priceAggregator; // collateral => Mainnet Chainlink aggregator for collateral's(Vault) underlying
    ITellorCaller internal tellorCaller; // Wrapper contract that calls the Tellor system
    mapping(address => bytes32) public tellorQueryId; // collateral => Tellor query ID

    // Core Liquity contracts
    ICollateralConfig public collateralConfig;

    // Use to convert a price answer to an 18-digit precision uint
    uint public constant TARGET_DIGITS = 18;
    // legacy Tellor "request IDs" use 6 decimals, newer Tellor "query IDs" use 18 decimals
    uint public constant TELLOR_DIGITS = 18;

    // Maximum deviation allowed between two consecutive Chainlink oracle prices. 18-digit precision.
    uint public constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%

    /*
     * The maximum relative price difference between two oracle responses allowed in order for the PriceFeed
     * to return to using the Chainlink oracle. 18-digit precision.
     */
    uint public constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%

    // The last good price seen from an oracle by Liquity for each collateral
    mapping(address => uint) public lastGoodPrice;

    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 timestamp;
        bool success;
        uint8 decimals;
    }

    struct TellorResponse {
        bool ifRetrieve;
        uint256 value;
        uint256 timestamp;
        bool success;
    }

    enum Status {
        chainlinkWorking,
        usingTellorChainlinkUntrusted,
        bothOraclesUntrusted,
        usingTellorChainlinkFrozen,
        usingChainlinkTellorUntrusted
    }

    // The current status of the PriceFeed for each collateral, which determines the conditions for the next price fetch attempt
    mapping(address => Status) public status;

    event CollateralConfigAddressChanged(address _newCollateralConfigAddress);
    event PriceFeedStatusChanged(address _collateral, Status newStatus);

    // --- Dependency setters ---

    function setAddresses(
        address _collateralConfigAddress,
        address[] calldata _priceAggregatorAddresses,
        address _tellorCallerAddress,
        bytes32[] calldata _tellorQueryIds
    ) external onlyOwner {
        require(!initialized, "Can only initialize once");
        checkContract(_collateralConfigAddress);
        collateralConfig = ICollateralConfig(_collateralConfigAddress);
        emit CollateralConfigAddressChanged(_collateralConfigAddress);

        address[] memory collaterals = collateralConfig.getAllowedCollaterals();
        uint256 numCollaterals = collaterals.length;
        require(numCollaterals != 0, "At least one collateral required");
        require(_priceAggregatorAddresses.length == numCollaterals, "Array lengths must match");
        require(_tellorQueryIds.length == numCollaterals, "Array lengths must match");

        checkContract(_tellorCallerAddress);
        tellorCaller = ITellorCaller(_tellorCallerAddress);

        for (uint256 i = 0; i < numCollaterals; i++) {
            address collateral = collaterals[i];
            address priceAggregatorAddress = _priceAggregatorAddresses[i];
            bytes32 queryId = _tellorQueryIds[i];

            checkContract(priceAggregatorAddress);
            require(queryId != bytes32(0), "Invalid Tellor Query ID");

            priceAggregator[collateral] = AggregatorV3Interface(priceAggregatorAddress);
            tellorQueryId[collateral] = queryId;

            // Explicitly set initial system status
            status[collateral] = Status.chainlinkWorking;

            // Get an initial price from Chainlink to serve as first reference for lastGoodPrice
            ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(collateral);

            require(
                !_chainlinkIsBroken(chainlinkResponse) &&
                    !_chainlinkIsFrozen(chainlinkResponse, collateral),
                "PriceFeed: Chainlink must be working and current"
            );
            _storeChainlinkPrice(collateral, chainlinkResponse);
        }

        initialized = true;
    }

    // Admin function to update the Chainlink aggregator address for a particular collateral.
    //
    // !!!PLEASE USE EXTREME CARE AND CAUTION!!!
    function updateChainlinkAggregator(
        address _collateral,
        address _priceAggregatorAddress
    ) external override {
        _requireCallerIsOwnerOrCollateralConfig();
        _requireValidCollateralAddress(_collateral);
        checkContract(_priceAggregatorAddress);
        priceAggregator[_collateral] = AggregatorV3Interface(_priceAggregatorAddress);

        // Explicitly set initial system status
        status[_collateral] = Status.chainlinkWorking;

        // Get an initial price from Chainlink to serve as first reference for lastGoodPrice
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(_collateral);

        require(
            !_chainlinkIsBroken(chainlinkResponse) &&
                !_chainlinkIsFrozen(chainlinkResponse, _collateral),
            "PriceFeed: Chainlink must be working and current"
        );

        _storeChainlinkPrice(_collateral, chainlinkResponse);
    }

    // Admin function to update the TellorCaller.
    //
    // !!!PLEASE USE EXTREME CARE AND CAUTION!!!
    function updateTellorCaller(address _tellorCallerAddress) external onlyOwner {
        checkContract(_tellorCallerAddress);
        tellorCaller = ITellorCaller(_tellorCallerAddress);
    }

    // Admin function to update the Tellor query ID for a particular collateral.
    //
    // !!!PLEASE USE EXTREME CARE AND CAUTION!!!
    function updateTellorQueryID(address _collateral, bytes32 _queryId) external override {
        _requireCallerIsOwnerOrCollateralConfig();
        _requireValidCollateralAddress(_collateral);
        require(_queryId != bytes32(0), "Invalid Tellor Query ID");
        tellorQueryId[_collateral] = _queryId;
    }

    // --- Functions ---

    /*
     * fetchPrice():
     * Returns the latest price obtained from the Oracle. Called by Liquity functions that require a current price.
     *
     * Also callable by anyone externally.
     *
     * Non-view function - it stores the last good price seen by Liquity.
     *
     * Uses a main oracle (Chainlink) and a fallback oracle (Tellor) in case Chainlink fails. If both fail,
     * it uses the last good price seen by Liquity.
     *
     */
    function fetchPrice(address _collateral) external override returns (uint) {
        _requireValidCollateralAddress(_collateral);

        // Get current and previous price data from Chainlink, and current price data from Tellor
        ChainlinkResponse memory chainlinkResponse = _getCurrentChainlinkResponse(_collateral);

        uint _lastGoodSharePrice = _calculateVaultShareUSDPrice(
            _collateral,
            lastGoodPrice[_collateral]
        );

        TellorResponse memory tellorResponse = _getCurrentTellorResponse(_collateral);

        // --- CASE 1: System fetched last price from Chainlink  ---
        if (status[_collateral] == Status.chainlinkWorking) {
            // If Chainlink is broken, try Tellor
            if (_chainlinkIsBroken(chainlinkResponse)) {
                // If Tellor is broken then both oracles are untrusted, so return the last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(_collateral, Status.bothOraclesUntrusted);
                    return _lastGoodSharePrice;
                }
                /*
                 * If Tellor is only frozen but otherwise returning valid data, return the last good price.
                 * Tellor may need to be tipped to return current data.
                 */
                if (_tellorIsFrozen(tellorResponse, _collateral)) {
                    _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);
                    return _lastGoodSharePrice;
                }

                // If Chainlink is broken and Tellor is working, switch to Tellor and return current Tellor price
                _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);

                uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
            }

            // If Chainlink is frozen, try Tellor
            if (_chainlinkIsFrozen(chainlinkResponse, _collateral)) {
                // If Tellor is broken too, remember Tellor broke, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(_collateral, Status.usingChainlinkTellorUntrusted);
                    return _lastGoodSharePrice;
                }

                // If Tellor is frozen or working, remember Chainlink froze, and switch to Tellor
                _changeStatus(_collateral, Status.usingTellorChainlinkFrozen);

                if (_tellorIsFrozen(tellorResponse, _collateral)) {
                    return _lastGoodSharePrice;
                }

                // If Tellor is working, use it
                uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
            }

            // If Chainlink price has changed by > 50% between two consecutive rounds, compare it to Tellor's price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, lastGoodPrice[_collateral])) {
                // If Tellor is broken, both oracles are untrusted, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(_collateral, Status.bothOraclesUntrusted);
                    return _lastGoodSharePrice;
                }

                // If Tellor is frozen, switch to Tellor and return last good price
                if (_tellorIsFrozen(tellorResponse, _collateral)) {
                    _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);
                    return _lastGoodSharePrice;
                }

                /*
                 * If Tellor is live and both oracles have a similar price, conclude that Chainlink's large price deviation between
                 * two consecutive rounds was likely a legitmate market price movement, and so continue using Chainlink
                 */
                if (_bothOraclesSimilarPrice(chainlinkResponse, tellorResponse)) {
                    uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                    return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
                }

                // If Tellor is live but the oracles differ too much in price, conclude that Chainlink's initial price deviation was
                // an oracle failure. Switch to Tellor, and use Tellor price
                _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);

                uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
            }

            // If Chainlink is working and Tellor is broken, remember Tellor is broken
            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(_collateral, Status.usingChainlinkTellorUntrusted);
            }

            // If Chainlink is working, return Chainlink current price (no status change)
            uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
            return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
        }

        // --- CASE 2: The system fetched last price from Tellor ---
        if (status[_collateral] == Status.usingTellorChainlinkUntrusted) {
            // If both Tellor and Chainlink are live, unbroken, and reporting similar prices, switch back to Chainlink
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    tellorResponse,
                    _collateral
                )
            ) {
                _changeStatus(_collateral, Status.chainlinkWorking);
                uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
            }

            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(_collateral, Status.bothOraclesUntrusted);
                return _lastGoodSharePrice;
            }

            /*
             * If Tellor is only frozen but otherwise returning valid data, just return the last good price.
             * Tellor may need to be tipped to return current data.
             */
            if (_tellorIsFrozen(tellorResponse, _collateral)) {
                return _lastGoodSharePrice;
            }

            // Otherwise, use Tellor price
            uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
            return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
        }

        // --- CASE 3: Both oracles were untrusted at the last price fetch ---
        if (status[_collateral] == Status.bothOraclesUntrusted) {
            /*
             * If both oracles are now live, unbroken and similar price, we assume that they are reporting
             * accurately, and so we switch back to Chainlink.
             */
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    tellorResponse,
                    _collateral
                )
            ) {
                _changeStatus(_collateral, Status.chainlinkWorking);
                uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
            }

            // Otherwise, return the last good price - both oracles are still untrusted (no status change)
            return _lastGoodSharePrice;
        }

        // --- CASE 4: Using Tellor, and Chainlink is frozen ---
        if (status[_collateral] == Status.usingTellorChainlinkFrozen) {
            if (_chainlinkIsBroken(chainlinkResponse)) {
                // If both Oracles are broken, return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(_collateral, Status.bothOraclesUntrusted);
                    return _lastGoodSharePrice;
                }

                // If Chainlink is broken, remember it and switch to using Tellor
                _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);

                if (_tellorIsFrozen(tellorResponse, _collateral)) {
                    return _lastGoodSharePrice;
                }

                // If Tellor is working, return Tellor current price
                uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
            }

            if (_chainlinkIsFrozen(chainlinkResponse, _collateral)) {
                // if Chainlink is frozen and Tellor is broken, remember Tellor broke, and return last good price
                if (_tellorIsBroken(tellorResponse)) {
                    _changeStatus(_collateral, Status.usingChainlinkTellorUntrusted);
                    return _lastGoodSharePrice;
                }

                // If both are frozen, just use lastGoodPrice
                if (_tellorIsFrozen(tellorResponse, _collateral)) {
                    return _lastGoodSharePrice;
                }

                // if Chainlink is frozen and Tellor is working, keep using Tellor (no status change)
                uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
            }

            // if Chainlink is live and Tellor is broken, remember Tellor broke, and return Chainlink price
            if (_tellorIsBroken(tellorResponse)) {
                _changeStatus(_collateral, Status.usingChainlinkTellorUntrusted);
                uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
            }

            // If Chainlink is live and Tellor is frozen, just use last good price (no status change) since we have no basis for comparison
            if (_tellorIsFrozen(tellorResponse, _collateral)) {
                return _lastGoodSharePrice;
            }

            // If Chainlink is live and Tellor is working, compare prices. Switch to Chainlink
            // if prices are within 5%, and return Chainlink price.
            if (_bothOraclesSimilarPrice(chainlinkResponse, tellorResponse)) {
                _changeStatus(_collateral, Status.chainlinkWorking);
                uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
            }

            // Otherwise if Chainlink is live but price not within 5% of Tellor, distrust Chainlink, and return Tellor price
            _changeStatus(_collateral, Status.usingTellorChainlinkUntrusted);
            uint storedTellorPrice = _storeTellorPrice(_collateral, tellorResponse);
            return _calculateVaultShareUSDPrice(_collateral, storedTellorPrice);
        }

        // --- CASE 5: Using Chainlink, Tellor is untrusted ---
        if (status[_collateral] == Status.usingChainlinkTellorUntrusted) {
            // If Chainlink breaks, now both oracles are untrusted
            if (_chainlinkIsBroken(chainlinkResponse)) {
                _changeStatus(_collateral, Status.bothOraclesUntrusted);
                return _lastGoodSharePrice;
            }

            // If Chainlink is frozen, return last good price (no status change)
            if (_chainlinkIsFrozen(chainlinkResponse, _collateral)) {
                return _lastGoodSharePrice;
            }

            // If Chainlink and Tellor are both live, unbroken and similar price, switch back to chainlinkWorking and return Chainlink price
            if (
                _bothOraclesLiveAndUnbrokenAndSimilarPrice(
                    chainlinkResponse,
                    tellorResponse,
                    _collateral
                )
            ) {
                _changeStatus(_collateral, Status.chainlinkWorking);
                uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
                return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
            }

            // If Chainlink is live but deviated >50% from it's previous price and Tellor is still untrusted, switch
            // to bothOraclesUntrusted and return last good price
            if (_chainlinkPriceChangeAboveMax(chainlinkResponse, lastGoodPrice[_collateral])) {
                _changeStatus(_collateral, Status.bothOraclesUntrusted);
                return _lastGoodSharePrice;
            }

            // Otherwise if Chainlink is live and deviated <50% from it's previous price and Tellor is still untrusted,
            // return Chainlink price (no status change)
            uint storedChainlinkPrice = _storeChainlinkPrice(_collateral, chainlinkResponse);
            return _calculateVaultShareUSDPrice(_collateral, storedChainlinkPrice);
        }
    }

    // --- Helper functions ---

    function _calculateVaultShareUSDPrice(
        address _collateral,
        uint _vaultAssetUnitPrice
    ) internal view returns (uint) {
        IERC4626 vault = IERC4626(_collateral);
        uint256 oneShare = 10 ** vault.decimals();
        uint256 assetsForOneShare = vault.convertToAssets(oneShare);
        return (assetsForOneShare * _vaultAssetUnitPrice) / 10 ** vault.decimals();
    }

    /* Chainlink is considered broken if its current or previous round data is in any way bad. We check the previous round
     * for two reasons:
     *
     * 1) It is necessary data for the price deviation check in case 1,
     * and
     * 2) Chainlink is the PriceFeed's preferred primary oracle - having two consecutive valid round responses adds
     * peace of mind when using or returning to Chainlink.
     */
    function _chainlinkIsBroken(
        ChainlinkResponse memory _currentResponse
    ) internal view returns (bool) {
        return _badChainlinkResponse(_currentResponse);
    }

    function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }
        // Check for an invalid roundId that is 0
        if (_response.roundId == 0) {
            return true;
        }
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }
        // Check for non-positive price
        if (_response.answer <= 0) {
            return true;
        }

        return false;
    }

    function _chainlinkIsFrozen(
        ChainlinkResponse memory _response,
        address _collateral
    ) internal view returns (bool) {
        return
            block.timestamp.sub(_response.timestamp) >
            collateralConfig.getCollateralChainlinkTimeout(_collateral);
    }

    function _chainlinkPriceChangeAboveMax(
        ChainlinkResponse memory _currentResponse,
        uint _lastGoodOraclePrice
    ) internal pure returns (bool) {
        uint currentScaledPrice = _scaleChainlinkPriceByDigits(
            uint256(_currentResponse.answer),
            _currentResponse.decimals
        );

        uint minPrice = LiquityMath._min(currentScaledPrice, _lastGoodOraclePrice);
        uint maxPrice = LiquityMath._max(currentScaledPrice, _lastGoodOraclePrice);

        /*
         * Use the larger price as the denominator:
         * - If price decreased, the percentage deviation is in relation to the the previous price.
         * - If price increased, the percentage deviation is in relation to the current price.
         */
        uint percentDeviation = maxPrice.sub(minPrice).mul(DECIMAL_PRECISION).div(maxPrice);

        // Return true if price has more than doubled, or more than halved.
        return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
    }

    function _tellorIsBroken(TellorResponse memory _response) internal view returns (bool) {
        // Check for response call reverted
        if (!_response.success) {
            return true;
        }
        // Check for an invalid timeStamp that is 0, or in the future
        if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {
            return true;
        }
        // Check for zero price
        if (_response.value == 0) {
            return true;
        }

        return false;
    }

    function _tellorIsFrozen(
        TellorResponse memory _tellorResponse,
        address _collateral
    ) internal view returns (bool) {
        return
            block.timestamp.sub(_tellorResponse.timestamp) >
            collateralConfig.getCollateralTellorTimeout(_collateral);
    }

    function _bothOraclesLiveAndUnbrokenAndSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        TellorResponse memory _tellorResponse,
        address _collateral
    ) internal view returns (bool) {
        // Return false if either oracle is broken or frozen
        if (
            _tellorIsBroken(_tellorResponse) ||
            _tellorIsFrozen(_tellorResponse, _collateral) ||
            _chainlinkIsBroken(_chainlinkResponse) ||
            _chainlinkIsFrozen(_chainlinkResponse, _collateral)
        ) {
            return false;
        }

        return _bothOraclesSimilarPrice(_chainlinkResponse, _tellorResponse);
    }

    function _bothOraclesSimilarPrice(
        ChainlinkResponse memory _chainlinkResponse,
        TellorResponse memory _tellorResponse
    ) internal pure returns (bool) {
        uint scaledChainlinkPrice = _scaleChainlinkPriceByDigits(
            uint256(_chainlinkResponse.answer),
            _chainlinkResponse.decimals
        );
        uint scaledTellorPrice = _scaleTellorPriceByDigits(_tellorResponse.value);

        // Get the relative price difference between the oracles. Use the lower price as the denominator, i.e. the reference for the calculation.
        uint minPrice = LiquityMath._min(scaledTellorPrice, scaledChainlinkPrice);
        uint maxPrice = LiquityMath._max(scaledTellorPrice, scaledChainlinkPrice);
        uint percentPriceDifference = maxPrice.sub(minPrice).mul(DECIMAL_PRECISION).div(minPrice);

        /*
         * Return true if the relative price difference is <= 5%: if so, we assume both oracles are probably reporting
         * the honest market price, as it is unlikely that both have been broken/hacked and are still in-sync.
         */
        return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
    }

    function _scaleChainlinkPriceByDigits(
        uint _price,
        uint _answerDigits
    ) internal pure returns (uint) {
        /*
         * Convert the price returned by the Chainlink oracle to an 18-digit decimal for use by Liquity.
         * At date of Liquity launch, Chainlink uses an 8-digit price, but we also handle the possibility of
         * future changes.
         *
         */
        uint price;
        if (_answerDigits >= TARGET_DIGITS) {
            // Scale the returned price value down to Liquity's target precision
            price = _price.div(10 ** (_answerDigits - TARGET_DIGITS));
        } else if (_answerDigits < TARGET_DIGITS) {
            // Scale the returned price value up to Liquity's target precision
            price = _price.mul(10 ** (TARGET_DIGITS - _answerDigits));
        }
        return price;
    }

    function _scaleTellorPriceByDigits(uint _price) internal pure returns (uint) {
        uint256 price = _price;
        if (TARGET_DIGITS > TELLOR_DIGITS) {
            price = price.mul(10 ** (TARGET_DIGITS - TELLOR_DIGITS));
        } else if (TARGET_DIGITS < TELLOR_DIGITS) {
            price = price.div(10 ** (TELLOR_DIGITS - TARGET_DIGITS));
        }
        return price;
    }

    function _changeStatus(address _collateral, Status _status) internal {
        status[_collateral] = _status;
        emit PriceFeedStatusChanged(_collateral, _status);
    }

    function _storePrice(address _collateral, uint _currentPrice) internal returns (uint) {
        lastGoodPrice[_collateral] = _currentPrice;
        emit LastGoodPriceUpdated(_collateral, _currentPrice);
        return _currentPrice;
    }

    function _storeTellorPrice(
        address _collateral,
        TellorResponse memory _tellorResponse
    ) internal returns (uint) {
        uint scaledTellorPrice = _scaleTellorPriceByDigits(_tellorResponse.value);
        return _storePrice(_collateral, scaledTellorPrice);
    }

    function _storeChainlinkPrice(
        address _collateral,
        ChainlinkResponse memory _chainlinkResponse
    ) internal returns (uint) {
        uint scaledChainlinkPrice = _scaleChainlinkPriceByDigits(
            uint256(_chainlinkResponse.answer),
            _chainlinkResponse.decimals
        );
        return _storePrice(_collateral, scaledChainlinkPrice);
    }

    // --- Oracle response wrapper functions ---

    function _getCurrentTellorResponse(
        address _collateral
    ) internal returns (TellorResponse memory tellorResponse) {
        try tellorCaller.getTellorCurrentValue(tellorQueryId[_collateral]) returns (
            bool ifRetrieve,
            uint256 value,
            uint256 _timestampRetrieved
        ) {
            // If call to Tellor succeeds, return the response and success = true
            tellorResponse.ifRetrieve = ifRetrieve;
            tellorResponse.value = value;
            tellorResponse.timestamp = _timestampRetrieved;
            tellorResponse.success = true;

            return (tellorResponse);
        } catch {
            // If call to Tellor reverts, return a zero response with success = false
            return (tellorResponse);
        }
    }

    function _getCurrentChainlinkResponse(
        address _collateral
    ) internal view returns (ChainlinkResponse memory chainlinkResponse) {
        // First, try to get current decimal precision:
        try priceAggregator[_collateral].decimals() returns (uint8 decimals) {
            // If call to Chainlink succeeds, record the current decimal precision
            chainlinkResponse.decimals = decimals;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }

        // Secondly, try to get latest price data:
        try priceAggregator[_collateral].latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 /* startedAt */,
            uint256 timestamp,
            uint80 /* answeredInRound */
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.timestamp = timestamp;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    // --- 'require' functions ---

    function _requireValidCollateralAddress(address _collateral) internal view {
        require(collateralConfig.isCollateralAllowed(_collateral), "Invalid collateral address");
    }

    function _requireCallerIsOwnerOrCollateralConfig() internal view {
        require(
            msg.sender == owner() || msg.sender == address(collateralConfig),
            "PriceFeed: Caller is neither owner no CollateralConfig"
        );
    }
}

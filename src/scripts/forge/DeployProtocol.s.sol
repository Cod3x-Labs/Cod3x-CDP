// SPDX-License-Identifier: BUSL-1.1

/// @dev Script for deploying protocol with real PriceFeed rather than PriceFeedTestnet.
/// FOR TESTS ONLY, do not use for actual deployment!

pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Script.sol";
import {ActivePool} from "../../contracts/ActivePool.sol";
import {BorrowerOperations} from "../../contracts/BorrowerOperations.sol";
import {BorrowerHelper} from "../../contracts/BorrowerHelper.sol";
import {CollateralConfig} from "../../contracts/CollateralConfig.sol";
import {CollSurplusPool} from "../../contracts/CollSurplusPool.sol";
import {CommunityIssuance} from "../../contracts/LQTY/CommunityIssuance.sol";
import {DefaultPool} from "../../contracts/DefaultPool.sol";
import {GasPool} from "../../contracts/GasPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "../../contracts/Dependencies/ISwapper.sol";
import {Leverager} from "../../contracts/Leverager.sol";
import {LiquidationHelper} from "../../contracts/LiquidationHelper.sol";
import {LUSDToken} from "../../contracts/LUSDToken.sol";
import {MockGovernance} from "../../contracts/TestContracts/MockGovernance.sol";
import {PriceFeed} from "../../contracts/PriceFeed.sol";
import {RedemptionHelper} from "../../contracts/RedemptionHelper.sol";
import {RewarderManager} from "../../contracts/RewarderManager.sol";
import {SortedTroves} from "../../contracts/SortedTroves.sol";
import {StabilityPool} from "../../contracts/StabilityPool.sol";
import {TroveManager} from "../../contracts/TroveManager.sol";
import {TellorCaller} from "../../contracts/Dependencies/TellorCaller.sol";

contract DeployProtocol is Script {
    ActivePool public activePool;
    BorrowerOperations public borrowerOperations;
    BorrowerHelper public borrowerHelper;
    CollateralConfig public collateralConfig;
    CollSurplusPool public collSurplusPool;
    CommunityIssuance public communityIssuance;
    DefaultPool public defaultPool;
    GasPool public gasPool;
    Leverager public leverager;
    LiquidationHelper public liquidationHelper;
    LUSDToken public lusdToken;
    PriceFeed public priceFeed;
    RedemptionHelper public redemptionHelper;
    RewarderManager public rewarderManager;
    SortedTroves public sortedTroves;
    StabilityPool public stabilityPool;
    TroveManager public troveManager;
    TellorCaller public tellorCaller;

    MockGovernance public governance;
    MockGovernance public guardian;

    address icl = 0x95177295A394f2b9B04545FFf58f4aF0673E839d;

    ISwapper public swapper;

    function run(address _lusdToken, address _swapper) public {
        activePool = new ActivePool();
        borrowerOperations = new BorrowerOperations();
        borrowerHelper = new BorrowerHelper();
        collateralConfig = new CollateralConfig();
        collSurplusPool = new CollSurplusPool();
        communityIssuance = new CommunityIssuance();
        defaultPool = new DefaultPool();
        gasPool = new GasPool();
        leverager = new Leverager();
        liquidationHelper = new LiquidationHelper();
        priceFeed = new PriceFeed();
        redemptionHelper = new RedemptionHelper();
        rewarderManager = new RewarderManager();
        sortedTroves = new SortedTroves();
        stabilityPool = new StabilityPool();
        troveManager = new TroveManager();
        tellorCaller = new TellorCaller(payable(0));

        governance = new MockGovernance();
        guardian = new MockGovernance();

        if (_lusdToken == address(0)) {
            lusdToken = new LUSDToken(
                address(troveManager),
                address(stabilityPool),
                address(borrowerOperations),
                address(governance),
                address(guardian)
            );
        } else {
            lusdToken = LUSDToken(_lusdToken);
        }

        swapper = ISwapper(_swapper);

        activePool.setAddresses(
            address(collateralConfig),
            address(borrowerOperations),
            address(troveManager),
            address(redemptionHelper),
            address(liquidationHelper),
            address(stabilityPool),
            address(defaultPool),
            address(collSurplusPool)
        );
        borrowerOperations.setAddresses(
            address(collateralConfig),
            address(troveManager),
            address(activePool),
            address(defaultPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeed),
            address(sortedTroves),
            address(lusdToken),
            address(governance),
            address(leverager),
            address(borrowerHelper)
        );
        borrowerHelper.setAddresses(
            address(borrowerOperations),
            address(troveManager),
            address(lusdToken)
        );
        collSurplusPool.setAddresses(
            address(collateralConfig),
            address(borrowerOperations),
            address(troveManager),
            address(liquidationHelper),
            address(activePool)
        );
        communityIssuance.setAddresses(icl, address(stabilityPool));
        defaultPool.setAddresses(address(collateralConfig), address(troveManager), address(activePool));
        liquidationHelper.setAddresses(
            activePool,
            defaultPool,
            troveManager,
            collateralConfig,
            stabilityPool,
            collSurplusPool,
            priceFeed,
            sortedTroves
        );
        redemptionHelper.setAddresses(
            activePool,
            defaultPool,
            troveManager,
            collateralConfig,
            IERC20(icl),
            priceFeed,
            lusdToken,
            sortedTroves,
            address(governance)
        );
        rewarderManager.setAddresses(address(troveManager));
        sortedTroves.setParams(address(troveManager), address(borrowerOperations));
        stabilityPool.setAddresses(
            address(borrowerOperations),
            address(collateralConfig),
            address(troveManager),
            address(liquidationHelper),
            address(activePool),
            address(lusdToken),
            address(sortedTroves),
            address(priceFeed),
            address(communityIssuance)
        );
        troveManager.setAddresses(
            address(borrowerOperations),
            address(collateralConfig),
            address(activePool),
            address(defaultPool),
            address(gasPool),
            address(collSurplusPool),
            address(priceFeed),
            address(lusdToken),
            address(sortedTroves),
            icl,
            address(rewarderManager),
            address(redemptionHelper),
            address(liquidationHelper)
        );

        leverager.setAddresses(
            address(borrowerOperations),
            address(collateralConfig),
            address(troveManager),
            address(activePool),
            address(defaultPool),
            address(priceFeed),
            address(lusdToken),
            address(swapper)
        );
    }
}

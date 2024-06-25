// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Script.sol";
import {ActivePool} from "../../contracts/ActivePool.sol";
import {BorrowerOperations} from "../../contracts/BorrowerOperations.sol";
import {CollateralConfig} from "../../contracts/CollateralConfig.sol";
import {CollSurplusPool} from "../../contracts/CollSurplusPool.sol";
import {CommunityIssuance} from "../../contracts/LQTY/CommunityIssuance.sol";
import {DefaultPool} from "../../contracts/DefaultPool.sol";
import {ERC20Mock} from "../../contracts/TestContracts/ERC20Mock.sol";
import {GasPool} from "../../contracts/GasPool.sol";
import {IdealSwapper} from "../../contracts/TestContracts/IdealSwapper.sol";
import {Leverager} from "../../contracts/Leverager.sol";
import {LiquidationHelper} from "../../contracts/LiquidationHelper.sol";
import {LUSDToken} from "../../contracts/LUSDToken.sol";
import {MockGovernance} from "../../contracts/TestContracts/MockGovernance.sol";
import {PriceFeedTestnet} from "../../contracts/TestContracts/PriceFeedTestnet.sol";
import {RedemptionHelper} from "../../contracts/RedemptionHelper.sol";
import {RewarderManager} from "../../contracts/RewarderManager.sol";
import {SortedTroves} from "../../contracts/SortedTroves.sol";
import {StabilityPool} from "../../contracts/StabilityPool.sol";
import {TroveManager} from "../../contracts/TroveManager.sol";

contract DeployTestProtocol is Script {
    ActivePool public activePool;
    BorrowerOperations public borrowerOperations;
    CollateralConfig public collateralConfig;
    CollSurplusPool public collSurplusPool;
    CommunityIssuance public communityIssuance;
    DefaultPool public defaultPool;
    GasPool public gasPool;
    Leverager public leverager;
    LiquidationHelper public liquidationHelper;
    LUSDToken public lusdToken;
    PriceFeedTestnet public priceFeed;
    RedemptionHelper public redemptionHelper;
    RewarderManager public rewarderManager;
    SortedTroves public sortedTroves;
    StabilityPool public stabilityPool;
    TroveManager public troveManager;

    MockGovernance public governance;
    MockGovernance public guardian;

    ERC20Mock public icl;

    IdealSwapper public swapper;

    function run() public {
        activePool = new ActivePool();
        borrowerOperations = new BorrowerOperations();
        collateralConfig = new CollateralConfig();
        collSurplusPool = new CollSurplusPool();
        communityIssuance = new CommunityIssuance();
        defaultPool = new DefaultPool();
        gasPool = new GasPool();
        leverager = new Leverager();
        liquidationHelper = new LiquidationHelper();
        priceFeed = new PriceFeedTestnet();
        redemptionHelper = new RedemptionHelper();
        rewarderManager = new RewarderManager();
        sortedTroves = new SortedTroves();
        stabilityPool = new StabilityPool();
        troveManager = new TroveManager();

        governance = new MockGovernance();
        guardian = new MockGovernance();

        icl = new ERC20Mock("Ironclad", "ICL", 18, msg.sender, 0);

        lusdToken = new LUSDToken(
            address(troveManager),
            address(stabilityPool),
            address(borrowerOperations),
            address(governance),
            address(guardian)
        );

        swapper = new IdealSwapper(collateralConfig, priceFeed, address(lusdToken));

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
            address(leverager)
        );
        collSurplusPool.setAddresses(
            address(collateralConfig),
            address(borrowerOperations),
            address(troveManager),
            address(liquidationHelper),
            address(activePool)
        );
        communityIssuance.setAddresses(address(icl), address(stabilityPool));
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
            icl,
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
            address(icl),
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

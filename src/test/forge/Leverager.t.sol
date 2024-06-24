// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Test.sol";
import {BorrowerOperations} from "../../contracts/BorrowerOperations.sol";
import {CollateralConfig} from "../../contracts/CollateralConfig.sol";
import {DeployTestProtocol} from "../../scripts/forge/DeployTestProtocol.s.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";
import {Leverager} from "../../contracts/Leverager.sol";
import {PriceFeedTestnet} from "../../contracts/TestContracts/PriceFeedTestnet.sol";
import {TroveManager, TroveStatus} from "../../contracts/TroveManager.sol";

contract LeveragerTest is Test {
    BorrowerOperations borrowerOperations;
    CollateralConfig collateralConfig;
    Leverager leverager;
    IERC20 lusdToken;
    PriceFeedTestnet priceFeed;
    TroveManager troveManager;

    IERC20 icl;
    uint[] mcrs = [1.08 ether];
    uint[] ccrs = [1.2 ether];
    uint[] debtLimits = [type(uint).max];
    uint[] chainlinkTimeouts = [4 hours];
    uint[] tellorTimeouts = [4 hours];

    function setUp() public {
        DeployTestProtocol testDeployer = new DeployTestProtocol();
        testDeployer.run();

        borrowerOperations = testDeployer.borrowerOperations();
        collateralConfig = testDeployer.collateralConfig();
        leverager = testDeployer.leverager();
        lusdToken = IERC20(address(testDeployer.lusdToken()));
        priceFeed = testDeployer.priceFeed();
        troveManager = testDeployer.troveManager();
        icl = IERC20(address(testDeployer.icl()));

        vm.startPrank(address(testDeployer));
        collateralConfig.initialize(
            _collaterals(), mcrs, ccrs, debtLimits, chainlinkTimeouts, tellorTimeouts, address(priceFeed)
        );

        _initializeLeverager();

        priceFeed.setPrice(address(icl), 1e18);

        vm.stopPrank();
        icl.approve(address(borrowerOperations), type(uint).max);
        borrowerOperations.openTrove(address(icl), 10_000 ether, 0.005 ether, 100 ether, address(0), address(0));
    }

    function _collaterals() internal view returns (address[] memory) {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(icl);
        return collaterals;
    }

    function _initializeLeverager() internal {
        Leverager.SwapPath memory path;
        address[] memory tokens = new address[](2);
        tokens[0] = address(lusdToken);
        tokens[1] = address(icl);
        path.tokens = tokens;
        Leverager.Exchange[] memory exchanges = new Leverager.Exchange[](1);
        exchanges[0] = Leverager.Exchange(Leverager.ExchangeType.UniV2, address(leverager));
        path.exchanges = exchanges;
        leverager.setSwapPath(address(lusdToken), address(icl), path);

        path.tokens[0] = address(icl);
        path.tokens[1] = address(lusdToken);
        leverager.setSwapPath(address(icl), address(lusdToken), path);
    }

    function testLeverUp() public {
        icl.transfer(address(1), 1000 ether);
        vm.startPrank(address(1));
        icl.approve(address(leverager), type(uint).max);

        leverager.leverToTargetCRWithNIterations(
            address(icl), 1.3 ether, 2, 140 ether, 0.005 ether, address(0), address(0), 1 ether, 0.99 ether
        );
        vm.stopPrank();

        assertEq(troveManager.getTroveStatus(address(1), address(icl)), uint(TroveStatus.active));
    }
}

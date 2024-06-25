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

        address whale = makeAddr("whale");
        deal(address(icl), whale, 10_000 ether);
        vm.startPrank(whale);
        icl.approve(address(borrowerOperations), type(uint).max);
        borrowerOperations.openTrove(address(icl), 10_000 ether, 0.005 ether, 100 ether, address(0), address(0));
        vm.stopPrank();
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

    function testLeverToTargetCRWithNIterations(uint collIndex, uint targetCR, uint n, uint collValue) public {
        n = bound(n, 1, 15);

        collIndex = bound(collIndex, 0, _collaterals().length - 1);
        IERC20 coll = IERC20(_collaterals()[collIndex]);
        targetCR = bound(targetCR, collateralConfig.getCollateralMCR(address(coll)), 2.5 ether);
        collValue = bound(collValue, 100 * targetCR + 1 ether, 2500 ether);
        coll.approve(address(leverager), collValue);

        (uint collPrice, uint collAmount) = _dealCollAmountForValue(address(coll), collValue, address(this));
        leverager.leverToTargetCRWithNIterations(
            address(coll), targetCR, n, collAmount, 0.005 ether, address(0), address(0), 1 ether, 1 ether
        );

        assertEq(troveManager.getTroveStatus(address(this), address(coll)), 1);

        assertEq(coll.balanceOf(address(leverager)), 0);
        assertEq(lusdToken.balanceOf(address(leverager)), 0);

        assertApproxEqAbs(troveManager.getCurrentICR(address(this), address(coll), collPrice), targetCR, 0.0001 ether);
    }

    function testDeleverAndCloseTrove(uint collIndex, uint targetCR, uint n, uint collValue) public {
        n = bound(n, 1, 15);

        collIndex = bound(collIndex, 0, _collaterals().length - 1);
        IERC20 coll = IERC20(_collaterals()[collIndex]);
        targetCR = bound(targetCR, collateralConfig.getCollateralMCR(address(coll)), 1.75 ether);
        collValue = bound(collValue, 110 * targetCR + 1 ether, 2500 ether);
        coll.approve(address(leverager), collValue);

        (uint collPrice, uint collAmount) = _dealCollAmountForValue(address(coll), collValue, address(this));
        leverager.leverToTargetCRWithNIterations(
            address(coll), targetCR, n, collAmount, 0.005 ether, address(0), address(0), 1 ether, 1 ether
        );

        uint ernBalance = lusdToken.balanceOf(address(this));
        lusdToken.approve(address(leverager), ernBalance);
        leverager.deleverAndCloseTrove(address(coll), ernBalance, address(0), address(0), 1 ether, 1 ether);

        assertEq(troveManager.getTroveStatus(address(this), address(coll)), 2);
        assertEq(troveManager.getTroveDebt(address(this), address(coll)), 0);

        assertEq(coll.balanceOf(address(leverager)), 0);
        assertEq(lusdToken.balanceOf(address(leverager)), 0);

        uint dollarValueRecovered = lusdToken.balanceOf(address(this))
            + coll.balanceOf(address(this)) * 10 ** (18 - collateralConfig.getCollateralDecimals(address(coll))) * collPrice
                / 1 ether;
        assertApproxEqRel(dollarValueRecovered, collValue, 0.05 ether);
    }

    function _dealCollAmountForValue(address coll, uint collValue, address to)
        internal
        returns (uint collPrice, uint collAmount)
    {
        collPrice = priceFeed.fetchPrice(coll);
        collAmount = collValue * 10 ** collateralConfig.getCollateralDecimals(coll) / collPrice;
        deal(coll, to, collAmount);
    }
}

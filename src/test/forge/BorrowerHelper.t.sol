// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Test.sol";
import {BorrowerOperations} from "../../contracts/BorrowerOperations.sol";
import {BorrowerHelper} from "../../contracts/BorrowerHelper.sol";
import {CollateralConfig} from "../../contracts/CollateralConfig.sol";
import {DeployTestProtocol} from "../../scripts/forge/DeployTestProtocol.s.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";
import {Leverager} from "../../contracts/Leverager.sol";
import {PriceFeedTestnet} from "../../contracts/TestContracts/PriceFeedTestnet.sol";
import {TroveManager, TroveStatus} from "../../contracts/TroveManager.sol";

import {ReaperFeeController} from "../../lib/vault-v2/src/ReaperFeeController.sol";
import {ReaperVaultERC4626} from "../../lib/vault-v2/src/ReaperVaultERC4626.sol";

contract BorrowerHelperTest is Test {
    BorrowerOperations borrowerOperations;
    BorrowerHelper borrowerHelper;
    CollateralConfig collateralConfig;
    Leverager leverager;
    IERC20 lusdToken;
    PriceFeedTestnet priceFeed;
    TroveManager troveManager;
    address governance;
    address guardian;
    address whale;

    IERC20 icl;
    ReaperVaultERC4626 iclVault;
    uint[] mcrs = [1.08 ether];
    uint[] ccrs = [1.2 ether];
    uint[] debtLimits = [type(uint).max];
    uint[] chainlinkTimeouts = [4 hours];
    uint[] tellorTimeouts = [4 hours];

    function setUp() public {
        DeployTestProtocol testDeployer = new DeployTestProtocol();
        testDeployer.run();

        borrowerOperations = testDeployer.borrowerOperations();
        borrowerHelper = testDeployer.borrowerHelper();
        collateralConfig = testDeployer.collateralConfig();
        leverager = testDeployer.leverager();
        lusdToken = IERC20(address(testDeployer.lusdToken()));
        priceFeed = testDeployer.priceFeed();
        troveManager = testDeployer.troveManager();
        icl = IERC20(address(testDeployer.icl()));
        governance = address(testDeployer.governance());
        guardian = address(testDeployer.guardian());

        address[] memory strategists = new address[](1);
        strategists[0] = guardian;
        address[] memory multisigRoles = new address[](3);
        multisigRoles[0] = governance;
        multisigRoles[1] = governance;
        multisigRoles[2] = guardian;

        ReaperFeeController feeController = new ReaperFeeController();
        iclVault = new ReaperVaultERC4626(
            address(icl),
            "Ironclad vault",
            "rf-ICL",
            type(uint).max,
            0,
            governance,
            strategists,
            multisigRoles,
            address(feeController)
        );

        vm.startPrank(address(testDeployer));
        collateralConfig.initialize(
            _collaterals(), mcrs, ccrs, debtLimits, chainlinkTimeouts, tellorTimeouts, address(priceFeed)
        );

        priceFeed.setPrice(address(iclVault), 1e18);

        vm.stopPrank();

        whale = makeAddr("whale");
        deal(address(icl), whale, 1e26 ether);
        vm.startPrank(whale);
        icl.approve(address(borrowerHelper), type(uint).max);
        borrowerHelper.openTrove(address(iclVault), 1e26 ether, 0.005 ether, 100 ether, address(0), address(0));
        vm.stopPrank();
    }

    function testOpenTrove(uint collAmount, uint targetCR) public {
        uint MCR = collateralConfig.getCollateralMCR(address(iclVault));
        targetCR = bound(targetCR, MCR, 5 ether);
        collAmount = bound(collAmount, 100 * targetCR + 1 ether, 1e24);
        deal(address(icl), address(this), collAmount);
        icl.approve(address(borrowerHelper), collAmount);

        uint debt = collAmount * 1e18 / targetCR - borrowerOperations.LUSD_GAS_COMPENSATION();
        debt -= troveManager.getBorrowingFeeWithDecay(debt);
        borrowerHelper.openTrove(address(iclVault), collAmount, 0.005 ether, debt, address(0), address(0));

        assertApproxEqAbs(troveManager.getCurrentICR(address(this), address(iclVault), 1e18), targetCR, 0.01 ether);
    }

    function testCloseTrove(uint collAmount, uint targetCR) public {
        uint MCR = collateralConfig.getCollateralMCR(address(iclVault));
        targetCR = bound(targetCR, MCR, 5 ether);
        collAmount = bound(collAmount, 100 * targetCR + 1 ether, 1e24);
        deal(address(icl), address(this), collAmount);
        icl.approve(address(borrowerHelper), collAmount);

        uint debt = collAmount * 1e18 / targetCR - borrowerOperations.LUSD_GAS_COMPENSATION();
        debt -= troveManager.getBorrowingFeeWithDecay(debt);
        borrowerHelper.openTrove(address(iclVault), collAmount, 0.005 ether, debt, address(0), address(0));

        // give back fee
        deal(address(lusdToken), address(this), lusdToken.balanceOf(address(this)) + debt * 1.005 ether / 1e18);

        lusdToken.approve(address(borrowerHelper), lusdToken.balanceOf(address(this)));
        borrowerHelper.closeTrove(address(iclVault));

        assertEq(troveManager.getTroveStatus(address(this), address(iclVault)), uint(TroveStatus.closedByOwner));
        assertEq(icl.balanceOf(address(this)), collAmount);
    }

    /*function testAdjustTrove(
        uint collAmount,
        uint targetCR,
        uint newTargetCR,
        uint collTopUp,
        uint collWithdrawal,
        uint lusdChange,
        bool isDebtIncrease
    ) public {
        uint MCR = collateralConfig.getCollateralMCR(address(iclVault));
        targetCR = bound(targetCR, MCR, 5 ether);
        newTargetCR = bound(newTargetCR, MCR, 5 ether);
        collAmount = bound(collAmount, 100 * targetCR + 1 ether, 1e24);

        vm.assume(collTopUp != 0 || collWithdrawal != 0 || lusdChange != 0);
        vm.assume(_collTopUp == 0 || _collWithdrawal == 0);

        deal(address(icl), address(this), collAmount);
        icl.approve(address(borrowerHelper), collAmount);

        uint debt = collAmount * 1e18 / targetCR - borrowerOperations.LUSD_GAS_COMPENSATION();
        debt -= troveManager.getBorrowingFeeWithDecay(debt);
        borrowerHelper.openTrove(address(iclVault), collAmount, 0.005 ether, debt, address(0), address(0));
        borrowerHelper.adjustTrove(address(iclVault), 0.005 ether, collTopUp, collWithdrawal, lusdChange, isDebtIncrease, address(0), address(0));
    }*/

    /*function testClaimCollateral() public {
        vm.prank(whale);
        borrowerOperations.withdrawColl(address(iclVault), 1e26 - 130 ether, address(0), address(0));

        uint collAmount = 120 ether;
        deal(address(icl), address(this), collAmount);
        icl.approve(address(borrowerHelper), collAmount);
        borrowerHelper.openTrove(address(iclVault), collAmount, 0.005 ether, 100 ether, address(0), address(0));

        priceFeed.setPrice(address(iclVault), 0.95 ether);
        troveManager.liquidateTroves(address(iclVault), 2);

        console.log(iclVault.balanceOf(address(this)));
        borrowerHelper.claimCollateral(address(iclVault));
        console.log(iclVault.balanceOf(address(this)));
    }*/

    function _collaterals() internal view returns (address[] memory) {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(iclVault);
        return collaterals;
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

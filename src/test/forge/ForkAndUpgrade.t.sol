// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.23;

import "../../lib/forge-std/src/Test.sol";
import "../../scripts/forge/DeployProtocol.s.sol";
import {AggregatorV3Interface} from "../../contracts/Dependencies/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockAggregator} from "../../contracts/TestContracts/MockAggregator.sol";
import {ReaperVaultERC4626} from "../../lib/vault-v2/src/ReaperVaultERC4626.sol";

contract ForkAndUpgrade is Test {
    address iUSD = 0xA70266C8F8Cf33647dcFEE763961aFf418D9E1E4;
    address swapper = 0xF86F3Cba7034d0072725b480b09BC84f3851E119;

    // arrays for CollateralConfig initialization
    address[] initialCollaterals = [
        0x3117c7854d11cB0216c82B81934CAaFe0722BB44 // WETH vault
    ];
    uint256[] mcrs = [1.08 ether];
    uint256[] ccrs = [1.2 ether];
    uint256[] debtLimits = [type(uint256).max];
    uint256[] chainlinkTimeouts = [9 hours];
    uint256[] tellorTimeouts = [9 hours];

    // arays for PriceFeed initialization
    address[] priceAggregatorAddresses = [0x0c52eACEBe1E458943a7A458fdd6d436D805B34F];
    uint[] maxPriceDeviations = [0.5 ether];

    BorrowerHelper borrowerHelper;
    BorrowerOperations borrowerOperations;
    CollateralConfig collateralConfig;
    PriceFeed priceFeed;
    TroveManager troveManager;

    function setUp() public {
        // deploy new protocol
        vm.createSelectFork("https://mainnet.mode.network");
        DeployProtocol deployer = new DeployProtocol();
        deployer.run(iUSD, swapper);

        // get contracts
        borrowerHelper = deployer.borrowerHelper();
        borrowerOperations = deployer.borrowerOperations();
        collateralConfig = deployer.collateralConfig();
        priceFeed = deployer.priceFeed();
        troveManager = deployer.troveManager();

        // initialize CollateralConfig
        vm.startPrank(address(deployer));
        collateralConfig.initialize(
            initialCollaterals, mcrs, ccrs, debtLimits, chainlinkTimeouts, tellorTimeouts, address(priceFeed)
        );

        // initialize PriceFeed
        bytes32[] memory tellorQueryIds = new bytes32[](1);
        tellorQueryIds[0] = 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992;
        priceFeed.setAddresses(
            address(collateralConfig),
            priceAggregatorAddresses,
            address(deployer.tellorCaller()),
            tellorQueryIds,
            maxPriceDeviations
        );

        // test addNewCollateral function
        collateralConfig.addNewCollateral(
            0xF7BC8B00a065943dC8D7B63E9632D7F987731C05, // MODE vault
            1.2 ether,
            1.65 ether,
            type(uint256).max,
            27 hours,
            27 hours,
            0x8dd2D85C7c28F43F965AE4d9545189C7D022ED0e,
            0xc20aa4918a4df6b79e3048755a98597d65451dd1bc2dcb85f554456bcfafea20,
            0.5 ether
        );

        // upgrade protocol
        vm.stopPrank();
        vm.startPrank(LUSDToken(iUSD).governanceAddress());
        LUSDToken(iUSD).upgradeProtocol(
            address(deployer.troveManager()), address(deployer.stabilityPool()), address(deployer.borrowerOperations())
        );
        vm.stopPrank();

        // open initial troves to avoid CCR issue
        address whale = makeAddr("whale");
        address[] memory allowedCollaterals = collateralConfig.getAllowedCollaterals();
        for (uint256 i; i < allowedCollaterals.length; ++i) {
            address collateral = collateralConfig.getAllowedCollaterals()[i];
            (, uint256 collAmount) = _dealUnderlyingAmountForCollValue(collateral, 1_000_000 ether, whale);
            address underlying = ReaperVaultERC4626(collateral).asset();
            vm.startPrank(whale);
            IERC20(underlying).approve(address(borrowerHelper), type(uint).max);
            borrowerHelper.openTrove(collateral, collAmount, 0.005 ether, 100 ether, address(0), address(0));
            vm.stopPrank();
        }
    }

    function testOpenTrove(uint collIndex, uint collValue, uint targetCR) public {
        address collateral = _getRandColl(collIndex);

        // arithmetic calculations
        uint MCR = collateralConfig.getCollateralMCR(collateral);
        targetCR = bound(targetCR, MCR, 5 ether);
        collValue = bound(collValue, 100 * targetCR + 1 ether, 1e24);
        uint debt = collValue * 1e18 / targetCR - borrowerOperations.LUSD_GAS_COMPENSATION();
        debt -= troveManager.getBorrowingFeeWithDecay(debt);

        // deal coll
        (uint256 collPrice, uint256 collAmount) =
            _dealUnderlyingAmountForCollValue(collateral, collValue, address(this));

        // open trove
        address underlying = ReaperVaultERC4626(collateral).asset();
        IERC20(underlying).approve(address(borrowerHelper), collAmount);
        borrowerHelper.openTrove(collateral, collAmount, 0.005 ether, debt, address(0), address(0));

        // assert ICR matches targetCR (within 1%)
        assertApproxEqAbs(troveManager.getCurrentICR(address(this), collateral, collPrice), targetCR, 0.01 ether);
    }

    function testCanHandlePriceDeviation(uint priceDeviation, uint collIndex, uint collValue, uint targetCR) public {
        address collateral = _getRandColl(collIndex);
        priceDeviation = bound (priceDeviation, 0, priceFeed.maxPriceDeviation(collateral));

        AggregatorV3Interface aggregator = priceFeed.priceAggregator(collateral);
        (uint80 roundId, int256 answer,, uint256 updatedAt,) = aggregator.latestRoundData();

        MockAggregator mockAggregator = new MockAggregator();
        mockAggregator.setPrevRoundId(roundId);
        mockAggregator.setLatestRoundId(roundId + 1);
        mockAggregator.setUpdateTime(updatedAt + 1);
        mockAggregator.setPrevPrice(answer);
        // divide by 1e28 because lastGoodPrice and priceDeviation are 18 decimals but aggregator uses 8
        mockAggregator.setPrice(
            int(priceFeed.lastGoodPrice(collateral) * (1e18 + priceDeviation) / 1e28)
        );

        vm.prank(priceFeed.owner());
        priceFeed.updateChainlinkAggregator(collateral, address(mockAggregator));

        testOpenTrove(collIndex, collValue, targetCR);
        assertEq(uint(priceFeed.status(collateral)), uint(PriceFeed.Status.usingChainlinkTellorUntrusted));
    }

    // choose random (assuming collIndex is a fuzz param) allowed collateral
    function _getRandColl(uint collIndex) internal returns (address collateral) {
        address[] memory allowedCollaterals = collateralConfig.getAllowedCollaterals();
        collIndex = bound(collIndex, 0, allowedCollaterals.length - 1);
        collateral = allowedCollaterals[0];
    }

    function _dealUnderlyingAmountForCollValue(address collateral, uint collValue, address to)
        internal
        returns (uint collPrice, uint collAmount)
    {
        collPrice = priceFeed.fetchPrice(collateral);
        collAmount = priceFeed.lastAssetsPerShare(collateral) * collValue / collPrice;
        address underlying = ReaperVaultERC4626(collateral).asset();
        deal(underlying, to, collAmount);
    }
}

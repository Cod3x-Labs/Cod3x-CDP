const CollateralConfig = artifacts.require("./CollateralConfig.sol");
const SortedTroves = artifacts.require("./SortedTroves.sol");
const TroveManager = artifacts.require("./TroveManager.sol");
const RewarderManager = artifacts.require("./RewarderManager.sol");
const RedemptionHelper = artifacts.require("./RedemptionHelper.sol");
const LiquidationHelper = artifacts.require("./LiquidationHelper.sol");
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol");
const LUSDToken = artifacts.require("./LUSDToken.sol");
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const StabilityPool = artifacts.require("./StabilityPool.sol");
const GasPool = artifacts.require("./GasPool.sol");
const CollSurplusPool = artifacts.require("./CollSurplusPool.sol");
const FunctionCaller = artifacts.require("./TestContracts/FunctionCaller.sol");
const BorrowerOperations = artifacts.require("./BorrowerOperations.sol");
const BorrowerHelper = artifacts.require("./BorrowerHelper.sol")
const HintHelpers = artifacts.require("./HintHelpers.sol");
const Leverager = artifacts.require("./Leverager.sol");

const CommunityIssuance = artifacts.require("./CommunityIssuance.sol");

const ERC20 = artifacts.require("ERC20Mock.sol");
const Governance = artifacts.require("MockGovernance.sol");
const Guardian = artifacts.require("MockGuardian.sol");

const CommunityIssuanceTester = artifacts.require(
  "./CommunityIssuanceTester.sol",
);
const StabilityPoolTester = artifacts.require("./StabilityPoolTester.sol");
const ActivePoolTester = artifacts.require("./ActivePoolTester.sol");
const DefaultPoolTester = artifacts.require("./DefaultPoolTester.sol");
const LiquityMathTester = artifacts.require("./LiquityMathTester.sol");
const BorrowerOperationsTester = artifacts.require(
  "./BorrowerOperationsTester.sol",
);
const TroveManagerTester = artifacts.require("./TroveManagerTester.sol");
const LUSDTokenTester = artifacts.require("./LUSDTokenTester.sol");

const NonPayable = artifacts.require("./NonPayable.sol");

// Proxy scripts
const BorrowerOperationsScript = artifacts.require("BorrowerOperationsScript");
const BorrowerWrappersScript = artifacts.require("BorrowerWrappersScript");
const TroveManagerScript = artifacts.require("TroveManagerScript");
const StabilityPoolScript = artifacts.require("StabilityPoolScript");
const TokenScript = artifacts.require("TokenScript");
const {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  TroveManagerProxy,
  StabilityPoolProxy,
  SortedTrovesProxy,
  TokenProxy,
} = require("../utils/proxyHelpers.js");
const testHelpers = require("./testHelpers.js");
const toBN = testHelpers.TestHelper.toBN;
const dec = testHelpers.TestHelper.dec;

/* "Liquity core" consists of all contracts in the core Liquity system.

LQTY contracts consist of only those contracts related to the LQTY Token:

-the LQTY token
-the Lockup factory and lockup contracts
-the CommunityIssuance contract 
*/

class DeploymentHelper {
  static async deployLiquityCore() {
    return this.deployLiquityCoreHardhat();
  }

  static async deployLQTYContracts(multisigAddress) {
    return this.deployLQTYContractsHardhat(multisigAddress);
  }

  static async deployLiquityCoreHardhat() {
    const collateralConfig = await CollateralConfig.new();
    const priceFeedTestnet = await PriceFeedTestnet.new();
    const sortedTroves = await SortedTroves.new();
    const troveManager = await TroveManager.new();
    const rewarderManager = await RewarderManager.new();
    const redemptionHelper = await RedemptionHelper.new();
    const liquidationHelper = await LiquidationHelper.new();
    const activePool = await ActivePool.new();
    const stabilityPool = await StabilityPool.new();
    const gasPool = await GasPool.new();
    const defaultPool = await DefaultPool.new();
    const collSurplusPool = await CollSurplusPool.new();
    const functionCaller = await FunctionCaller.new();
    const borrowerOperations = await BorrowerOperations.new();
    const borrowerHelper = await BorrowerHelper.new();
    const hintHelpers = await HintHelpers.new();
    const leverager = await Leverager.new();
    const governance = await Governance.new();
    const guardian = await Guardian.new();
    const lusdToken = await LUSDToken.new(
      troveManager.address,
      stabilityPool.address,
      borrowerOperations.address,
      governance.address,
      guardian.address,
    );
    CollateralConfig.setAsDeployed(collateralConfig);
    LUSDToken.setAsDeployed(lusdToken);
    DefaultPool.setAsDeployed(defaultPool);
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet);
    SortedTroves.setAsDeployed(sortedTroves);
    TroveManager.setAsDeployed(troveManager);
    RewarderManager.setAsDeployed(rewarderManager);
    RedemptionHelper.setAsDeployed(redemptionHelper);
    LiquidationHelper.setAsDeployed(liquidationHelper);
    ActivePool.setAsDeployed(activePool);
    StabilityPool.setAsDeployed(stabilityPool);
    GasPool.setAsDeployed(gasPool);
    CollSurplusPool.setAsDeployed(collSurplusPool);
    FunctionCaller.setAsDeployed(functionCaller);
    BorrowerOperations.setAsDeployed(borrowerOperations);
    BorrowerHelper.setAsDeployed(borrowerHelper);
    HintHelpers.setAsDeployed(hintHelpers);
    Leverager.setAsDeployed(leverager);
    Governance.setAsDeployed(governance);
    Guardian.setAsDeployed(guardian);

    const coreContracts = {
      collateralConfig,
      priceFeedTestnet,
      lusdToken,
      sortedTroves,
      troveManager,
      rewarderManager,
      redemptionHelper,
      liquidationHelper,
      activePool,
      stabilityPool,
      gasPool,
      defaultPool,
      collSurplusPool,
      functionCaller,
      borrowerOperations,
      borrowerHelper,
      hintHelpers,
      leverager,
      governance,
      guardian,
    };
    return coreContracts;
  }

  static async deployTesterContractsHardhat() {
    const testerContracts = {};

    // Contract without testers (yet)
    testerContracts.collateralConfig = await CollateralConfig.new();
    testerContracts.priceFeedTestnet = await PriceFeedTestnet.new();
    testerContracts.sortedTroves = await SortedTroves.new();
    testerContracts.rewarderManager = await RewarderManager.new();
    testerContracts.redemptionHelper = await RedemptionHelper.new();
    testerContracts.liquidationHelper = await LiquidationHelper.new();
    // Actual tester contracts
    testerContracts.communityIssuance = await CommunityIssuanceTester.new();
    testerContracts.activePool = await ActivePoolTester.new();
    testerContracts.defaultPool = await DefaultPoolTester.new();
    testerContracts.stabilityPool = await StabilityPoolTester.new();
    testerContracts.gasPool = await GasPool.new();
    testerContracts.collSurplusPool = await CollSurplusPool.new();
    testerContracts.math = await LiquityMathTester.new();
    testerContracts.borrowerOperations = await BorrowerOperationsTester.new();
    testerContracts.borrowerHelper = await BorrowerHelper.new();
    testerContracts.troveManager = await TroveManagerTester.new();
    testerContracts.functionCaller = await FunctionCaller.new();
    testerContracts.hintHelpers = await HintHelpers.new();
    testerContracts.leverager = await Leverager.new();
    testerContracts.governance = await Governance.new();
    testerContracts.guardian = await Guardian.new();
    testerContracts.lusdToken = await LUSDTokenTester.new(
      testerContracts.troveManager.address,
      testerContracts.stabilityPool.address,
      testerContracts.borrowerOperations.address,
      testerContracts.governance.address,
      testerContracts.guardian.address,
    );
    return testerContracts;
  }

  static async deployLQTYContractsHardhat(multisigAddress) {
    const treasury = await NonPayable.new();
    const communityIssuance = await CommunityIssuance.new();

    CommunityIssuance.setAsDeployed(communityIssuance);

    const stakingToken = await ERC20.new(
      "OATH-ETH BPT",
      "BPT-OATH",
      18,
      multisigAddress,
      toBN(dec(1_000_000, 18)),
    );
    ERC20.setAsDeployed(stakingToken);
    const oathToken = await ERC20.new(
      "OATH Token",
      "OATH",
      18,
      multisigAddress,
      toBN(dec(1_000_000, 18)),
    );
    ERC20.setAsDeployed(oathToken);

    const LQTYContracts = {
      treasury,
      communityIssuance,
      stakingToken,
      oathToken,
    };
    return LQTYContracts;
  }

  static async deployLQTYTesterContractsHardhat(multisigAddress) {
    const treasury = await NonPayable.new();
    const communityIssuance = await CommunityIssuanceTester.new();

    CommunityIssuanceTester.setAsDeployed(communityIssuance);

    const stakingToken = await ERC20.new(
      "OATH-ETH BPT",
      "BPT-OATH",
      18,
      multisigAddress,
      toBN(dec(1000, 18)),
    );
    ERC20.setAsDeployed(stakingToken);
    const oathToken = await ERC20.new(
      "OATH Token",
      "OATH",
      18,
      multisigAddress,
      toBN(dec(1000, 18)),
    );
    ERC20.setAsDeployed(oathToken);

    const LQTYContracts = {
      treasury,
      communityIssuance,
      stakingToken,
      oathToken,
    };
    return LQTYContracts;
  }

  static async deployLUSDToken(contracts) {
    contracts.lusdToken = await LUSDToken.new(
      contracts.troveManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address,
      contracts.governance.address,
      contracts.guardian.address,
    );
    return contracts;
  }

  static async deployLUSDTokenTester(contracts) {
    contracts.lusdToken = await LUSDTokenTester.new(
      contracts.troveManager.address,
      contracts.stabilityPool.address,
      contracts.borrowerOperations.address,
      contracts.governance.address,
      contracts.guardian.address,
    );
    return contracts;
  }

  static async deployTestCollaterals(contracts) {
    const multisig = "0x3b410908e71Ee04e7dE2a87f8F9003AFe6c1c7cE"; // Arbitrary address for the multisig, which is not tested in this file
    const collateral1 = await ERC20.new(
      "Wrapped Ether",
      "wETH",
      12,
      multisig,
      0,
    ); // 12 decimal places
    const collateral2 = await ERC20.new(
      "Wrapped Bitcoin",
      "wBTC",
      8,
      multisig,
      0,
    ); // 8 decimal places
    contracts.collaterals = [collateral1, collateral2];
    return contracts;
  }

  static async deployProxyScripts(contracts, LQTYContracts, owner, users) {
    const proxies = await buildUserProxies(users);

    const borrowerWrappersScript = await BorrowerWrappersScript.new(
      contracts.borrowerOperations.address,
      contracts.collateralConfig.address,
      contracts.troveManager.address,
      contracts.stabilityPool.address,
    );
    contracts.borrowerWrappers = new BorrowerWrappersProxy(
      owner,
      proxies,
      borrowerWrappersScript.address,
    );

    const borrowerOperationsScript = await BorrowerOperationsScript.new(
      contracts.borrowerOperations.address,
    );
    contracts.borrowerOperations = new BorrowerOperationsProxy(
      owner,
      proxies,
      borrowerOperationsScript.address,
      contracts.borrowerOperations,
    );

    const troveManagerScript = await TroveManagerScript.new(
      contracts.troveManager.address,
    );
    contracts.troveManager = new TroveManagerProxy(
      owner,
      proxies,
      troveManagerScript.address,
      contracts.troveManager,
    );

    const stabilityPoolScript = await StabilityPoolScript.new(
      contracts.stabilityPool.address,
    );
    contracts.stabilityPool = new StabilityPoolProxy(
      owner,
      proxies,
      stabilityPoolScript.address,
      contracts.stabilityPool,
    );

    contracts.sortedTroves = new SortedTrovesProxy(
      owner,
      proxies,
      contracts.sortedTroves,
    );

    const lusdTokenScript = await TokenScript.new(contracts.lusdToken.address);
    contracts.lusdToken = new TokenProxy(
      owner,
      proxies,
      lusdTokenScript.address,
      contracts.lusdToken,
    );

    const lqtyTokenScript = await TokenScript.new(
      LQTYContracts.stakingToken.address,
    );
    LQTYContracts.stakingToken = new TokenProxy(
      owner,
      proxies,
      lqtyTokenScript.address,
      LQTYContracts.stakingToken,
    );
  }

  // Connect contracts to their dependencies
  static async connectCoreContracts(contracts, LQTYContracts) {
    await contracts.collateralConfig.initialize(
      [contracts.collaterals[0].address],
      [toBN(dec(12, 17))], // MCR for WETH at 120%
      [toBN(dec(165, 16))], // CCR for WETH at 165%
      [ethers.MaxUint256], // No debt limit
      [14400], // 4 hour Chainlink timeout
      [14400], // 4 hour Tellor timeout
      contracts.priceFeedTestnet.address,
    );

    // set TroveManager addr in SortedTroves
    await contracts.sortedTroves.setParams(
      contracts.troveManager.address,
      contracts.borrowerOperations.address,
    );

    // set contract addresses in the FunctionCaller
    await contracts.functionCaller.setTroveManagerAddress(
      contracts.troveManager.address,
    );
    await contracts.functionCaller.setSortedTrovesAddress(
      contracts.sortedTroves.address,
    );

    // set contracts in the Trove Manager
    await contracts.troveManager.setAddresses(
      contracts.borrowerOperations.address,
      contracts.collateralConfig.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.lusdToken.address,
      contracts.sortedTroves.address,
      LQTYContracts.stakingToken.address,
      contracts.rewarderManager.address,
      contracts.redemptionHelper.address,
      contracts.liquidationHelper.address,
    );

    await contracts.rewarderManager.setAddresses(
      contracts.troveManager.address,
    );

    await contracts.redemptionHelper.setAddresses(
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.troveManager.address,
      contracts.collateralConfig.address,
      LQTYContracts.stakingToken.address,
      contracts.priceFeedTestnet.address,
      contracts.lusdToken.address,
      contracts.sortedTroves.address,
      LQTYContracts.treasury.address,
    );

    await contracts.liquidationHelper.setAddresses(
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.troveManager.address,
      contracts.collateralConfig.address,
      contracts.stabilityPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.sortedTroves.address,
    );

    // set contracts in BorrowerOperations
    await contracts.borrowerOperations.setAddresses(
      contracts.collateralConfig.address,
      contracts.troveManager.address,
      contracts.activePool.address,
      contracts.defaultPool.address,
      contracts.gasPool.address,
      contracts.collSurplusPool.address,
      contracts.priceFeedTestnet.address,
      contracts.sortedTroves.address,
      contracts.lusdToken.address,
      LQTYContracts.treasury.address,
      contracts.leverager.address,
      contracts.borrowerHelper.address,
    );

    // set contracts in BorrowerHelper
    await contracts.borrowerHelper.setAddresses(
      contracts.borrowerOperations.address,
      contracts.troveManager.address,
      contracts.lusdToken.address
    );

    // set contracts in the Pools
    await contracts.stabilityPool.setAddresses(
      contracts.borrowerOperations.address,
      contracts.collateralConfig.address,
      contracts.troveManager.address,
      contracts.liquidationHelper.address,
      contracts.activePool.address,
      contracts.lusdToken.address,
      contracts.sortedTroves.address,
      contracts.priceFeedTestnet.address,
      LQTYContracts.communityIssuance.address,
    );

    await contracts.activePool.setAddresses(
      contracts.collateralConfig.address,
      contracts.borrowerOperations.address,
      contracts.troveManager.address,
      contracts.redemptionHelper.address,
      contracts.liquidationHelper.address,
      contracts.stabilityPool.address,
      contracts.defaultPool.address,
      contracts.collSurplusPool.address,
    );

    await contracts.defaultPool.setAddresses(
      contracts.collateralConfig.address,
      contracts.troveManager.address,
      contracts.activePool.address,
    );

    await contracts.collSurplusPool.setAddresses(
      contracts.collateralConfig.address,
      contracts.borrowerOperations.address,
      contracts.troveManager.address,
      contracts.liquidationHelper.address,
      contracts.activePool.address,
    );

    // set contracts in HintHelpers
    await contracts.hintHelpers.setAddresses(
      contracts.collateralConfig.address,
      contracts.sortedTroves.address,
      contracts.troveManager.address,
    );

    const mockChainlinkAggregator = await NonPayable.new();
    await contracts.collateralConfig.addNewCollateral(
      contracts.collaterals[1].address,
      toBN(dec(13, 17)), // MCR for WBTC at 130%
      toBN(dec(18, 17)), // CCR for WBTC at 180%
      ethers.MaxUint256, // No debt limit
      14400, // 4 hour Chainlink timeout
      14400, // 4 hour Tellor timeout
      mockChainlinkAggregator.address,
      "0x1", // mock Tellor query ID
    );
  }

  static async connectLQTYContracts(LQTYContracts) {
    // no-op
  }

  static async connectLQTYContractsToCore(LQTYContracts, coreContracts) {
    await LQTYContracts.communityIssuance.setAddresses(
      LQTYContracts.oathToken.address,
      coreContracts.stabilityPool.address,
    );
  }
}

module.exports = DeploymentHelper;

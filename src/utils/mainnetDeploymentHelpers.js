const fs = require('fs')

const ZERO_ADDRESS = '0x' + '0'.repeat(40)
const maxBytes32 = '0x' + 'f'.repeat(64)

class MainnetDeploymentHelper {
  constructor(configParams, deployerWallet) {
    this.configParams = configParams
    this.deployerWallet = deployerWallet
    this.hre = require("hardhat")
  }

  loadPreviousDeployment() {
    let previousDeployment = {}
    if (fs.existsSync(this.configParams.OUTPUT_FILE)) {
      console.log(`Loading previous deployment...`)
      previousDeployment = require('../' + this.configParams.OUTPUT_FILE)
    }

    return previousDeployment
  }

  saveDeployment(deploymentState) {
    const deploymentStateJSON = JSON.stringify(deploymentState, null, 2)
    fs.writeFileSync(this.configParams.OUTPUT_FILE, deploymentStateJSON)

  }
  // --- Deployer methods ---

  async getFactory(name) {
    const factory = await ethers.getContractFactory(name, this.deployerWallet)
    return factory
  }

  async sendAndWaitForTransaction(txPromise) {
    const tx = await txPromise
    const minedTx = await ethers.provider.waitForTransaction(tx.hash, this.configParams.TX_CONFIRMATIONS)

    return minedTx
  }

  async loadOrDeploy(factory, name, deploymentState, params=[]) {
    if (deploymentState[name] && deploymentState[name].address) {
      console.log(`Using previously deployed ${name} contract at address ${deploymentState[name].address}`)
      return await this.loadContract(factory, deploymentState[name].address)
    }
    return await this.deployContract(factory, name, deploymentState, params)
  }

  async loadContract(factory, address) {
    return new ethers.Contract(
      address,
      factory.interface,
      this.deployerWallet
    );
  }

  async deployContract(factory, name, deploymentState, params=[]) {
    const contract = await factory.deploy(...params, {gasPrice: this.configParams.GAS_PRICE})
    await this.deployerWallet.provider.waitForTransaction(contract.deployTransaction.hash, this.configParams.TX_CONFIRMATIONS)

    deploymentState[name] = {
      address: contract.address,
      txHash: contract.deployTransaction.hash
    }

    if (!this.configParams.isTest) this.saveDeployment(deploymentState)

    return contract
  }

  async deployLiquityCoreMainnet(tellorMasterAddr, governanceAddress, guardianAddress, deploymentState) {
    // Get contract factories
    const collateralConfigFactory = await this.getFactory("CollateralConfig")
    const priceFeedFactory = await this.getFactory("PriceFeed")
    const sortedTrovesFactory = await this.getFactory("SortedTroves")
    const troveManagerFactory = await this.getFactory("TroveManager")
    const activePoolFactory = await this.getFactory("ActivePool")
    const stabilityPoolFactory = await this.getFactory("StabilityPool")
    const gasPoolFactory = await this.getFactory("GasPool")
    const defaultPoolFactory = await this.getFactory("DefaultPool")
    const collSurplusPoolFactory = await this.getFactory("CollSurplusPool")
    const borrowerOperationsFactory = await this.getFactory("BorrowerOperations")
    const hintHelpersFactory = await this.getFactory("HintHelpers")
    const lusdTokenFactory = await this.getFactory("LUSDToken")
    const tellorCallerFactory = await this.getFactory("TellorCaller")
    const redemptionHelperFactory = await this.getFactory("RedemptionHelper")
    const liquidationHelperFactory = await this.getFactory("LiquidationHelper")
    const leveragerFactory = await this.getFactory("Leverager")

    // Deploy txs
    const collateralConfig = await this.loadOrDeploy(collateralConfigFactory, 'collateralConfig', deploymentState)
    const priceFeed = await this.loadOrDeploy(priceFeedFactory, 'priceFeed', deploymentState)
    const sortedTroves = await this.loadOrDeploy(sortedTrovesFactory, 'sortedTroves', deploymentState)
    const troveManager = await this.loadOrDeploy(troveManagerFactory, 'troveManager', deploymentState)
    const activePool = await this.loadOrDeploy(activePoolFactory, 'activePool', deploymentState)
    const stabilityPool = await this.loadOrDeploy(stabilityPoolFactory, 'stabilityPool', deploymentState)
    const gasPool = await this.loadOrDeploy(gasPoolFactory, 'gasPool', deploymentState)
    const defaultPool = await this.loadOrDeploy(defaultPoolFactory, 'defaultPool', deploymentState)
    const collSurplusPool = await this.loadOrDeploy(collSurplusPoolFactory, 'collSurplusPool', deploymentState)
    const borrowerOperations = await this.loadOrDeploy(borrowerOperationsFactory, 'borrowerOperations', deploymentState)
    const hintHelpers = await this.loadOrDeploy(hintHelpersFactory, 'hintHelpers', deploymentState)
    const tellorCaller = await this.loadOrDeploy(tellorCallerFactory, 'tellorCaller', deploymentState, [tellorMasterAddr])
    const redemptionHelper = await this.loadOrDeploy(redemptionHelperFactory, 'redemptionHelper', deploymentState)
    const liquidationHelper = await this.loadOrDeploy(liquidationHelperFactory, 'liquidationHelper', deploymentState)
    const leverager = await this.loadOrDeploy(leveragerFactory, 'leverager', deploymentState)

    let lusdToken
    if (this.configParams.liquityAddrs.LUSD_TOKEN) {
      lusdToken = await this.loadContract(lusdTokenFactory, this.configParams.liquityAddrs.LUSD_TOKEN)
    } else {
      const lusdTokenParams = [
        troveManager.address,
        stabilityPool.address,
        borrowerOperations.address,
        governanceAddress,
        guardianAddress
      ]
      lusdToken = await this.loadOrDeploy(
        lusdTokenFactory,
        'lusdToken',
        deploymentState,
        lusdTokenParams
      )
    }

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      if (!this.configParams.isTest) console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('collateralConfig', deploymentState)
      await this.verifyContract('priceFeed', deploymentState)
      await this.verifyContract('sortedTroves', deploymentState)
      await this.verifyContract('troveManager', deploymentState)
      await this.verifyContract('activePool', deploymentState)
      await this.verifyContract('stabilityPool', deploymentState)
      await this.verifyContract('gasPool', deploymentState)
      await this.verifyContract('defaultPool', deploymentState)
      await this.verifyContract('collSurplusPool', deploymentState)
      await this.verifyContract('borrowerOperations', deploymentState)
      await this.verifyContract('hintHelpers', deploymentState)
      await this.verifyContract('tellorCaller', deploymentState, [tellorMasterAddr])
      await this.verifyContract('redemptionHelper', deploymentState)
      await this.verifyContract('liquidationHelper', deploymentState)
      if (!this.configParams.liquityAddrs.LUSD_TOKEN) {
        await this.verifyContract('lusdToken', deploymentState, lusdTokenParams)
      }
      await this.verifyContract('leverager', deploymentState)
    }

    const coreContracts = {
      collateralConfig,
      priceFeed,
      lusdToken,
      sortedTroves,
      troveManager,
      activePool,
      stabilityPool,
      gasPool,
      defaultPool,
      collSurplusPool,
      borrowerOperations,
      hintHelpers,
      tellorCaller,
      redemptionHelper,
      liquidationHelper,
      leverager,
    }
    return coreContracts
  }

  async deployLQTYContractsMainnet(deploymentState) {
    const lqtyStakingFactory = await this.getFactory("LQTYStaking")
    const communityIssuanceFactory = await this.getFactory("CommunityIssuance")

    const lqtyStaking = await this.loadOrDeploy(lqtyStakingFactory, 'lqtyStaking', deploymentState)
    const communityIssuance = await this.loadOrDeploy(communityIssuanceFactory, 'communityIssuance', deploymentState)

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      if (!this.configParams.isTest) console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('lqtyStaking', deploymentState)
      await this.verifyContract('communityIssuance', deploymentState)
    }

    const LQTYContracts = {
      lqtyStaking,
      communityIssuance,
    }
    return LQTYContracts
  }

  async deployUnipoolMainnet(deploymentState) {
    const unipoolFactory = await this.getFactory("Unipool")
    const unipool = await this.loadOrDeploy(unipoolFactory, 'unipool', deploymentState)

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('unipool', deploymentState)
    }

    return unipool
  }

  async deployMultiTroveGetterMainnet(liquityCore, deploymentState) {
    const multiTroveGetterFactory = await this.getFactory("MultiTroveGetter")
    const multiTroveGetterParams = [
      liquityCore.collateralConfig.address,
      liquityCore.troveManager.address,
      liquityCore.sortedTroves.address
    ]
    const multiTroveGetter = await this.loadOrDeploy(
      multiTroveGetterFactory,
      'multiTroveGetter',
      deploymentState,
      multiTroveGetterParams
    )

    if (!this.configParams.ETHERSCAN_BASE_URL) {
      if (!this.configParams.isTest) console.log('No Etherscan Url defined, skipping verification')
    } else {
      await this.verifyContract('multiTroveGetter', deploymentState, multiTroveGetterParams)
    }

    return multiTroveGetter
  }
  // --- Connector methods ---

  async isOwnershipRenounced(contract) {
    const owner = await contract.owner()
    return owner == ZERO_ADDRESS
  }

  async isInitialized(contract) {
    const initialized = await contract.initialized()
    return initialized
  }

  async isOwnerDesiredAddress(contract, desiredAddress) {
    const owner = await contract.owner()
    return owner.toString().toUpperCase(owner) == desiredAddress.toString().toUpperCase()
  }
  // Connect contracts to their dependencies
  async connectCoreContractsMainnet(
    contracts,
    LQTYContracts,
    collaterals,
    governanceAddress,
    oathAddress,
    treasuryAddress
  ) {
    const gasPrice = this.configParams.GAS_PRICE
    // Initialize CollateralConfig
    await this.isInitialized(contracts.collateralConfig) ||
      await this.sendAndWaitForTransaction(contracts.collateralConfig.initialize(
        collaterals.map(c => c.address),
        collaterals.map(c => ethers.utils.parseEther(c.MCR)),
        collaterals.map(c => ethers.utils.parseEther(c.CCR)),
        collaterals.map(c => c.limit),
        collaterals.map(c => c.chainlinkTimeout),
        collaterals.map(c => c.tellorTimeout),
        contracts.activePool.address,
        contracts.priceFeed.address,
        {gasPrice}
      ))

    // Ensure CollateralConfig's owner is governanceAddress
    await this.isOwnerDesiredAddress(contracts.collateralConfig, governanceAddress) ||
      await this.sendAndWaitForTransaction(contracts.collateralConfig.transferOwnership(governanceAddress, {gasPrice}))

    // Initialize PriceFeed
    await this.isInitialized(contracts.priceFeed) ||
      await this.sendAndWaitForTransaction(contracts.priceFeed.setAddresses(
        contracts.collateralConfig.address,
        collaterals.map(c => c.chainlinkAggregatorAddress),
        contracts.tellorCaller.address,
        collaterals.map(c => c.tellorQueryID),
        {gasPrice}
      ))

    // Ensure PriceFeed's owner is governanceAddress
    await this.isOwnerDesiredAddress(contracts.priceFeed, governanceAddress) ||
      await this.sendAndWaitForTransaction(contracts.priceFeed.transferOwnership(governanceAddress, {gasPrice}))

    // set TroveManager addr in SortedTroves
    await this.isOwnershipRenounced(contracts.sortedTroves) ||
      await this.sendAndWaitForTransaction(contracts.sortedTroves.setParams(
        contracts.troveManager.address,
        contracts.borrowerOperations.address, 
	{gasPrice}
      ))

    // set contracts in the Trove Manager
    await this.isOwnershipRenounced(contracts.troveManager) ||
      await this.sendAndWaitForTransaction(contracts.troveManager.setAddresses(
        contracts.borrowerOperations.address,
        contracts.collateralConfig.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeed.address,
        contracts.lusdToken.address,
        contracts.sortedTroves.address,
        oathAddress,
        LQTYContracts.lqtyStaking.address,
        contracts.redemptionHelper.address,
        contracts.liquidationHelper.address,
	{gasPrice}
      ))

    // set contracts in RedemptionHelper
    await this.isOwnershipRenounced(contracts.redemptionHelper) ||
      await this.sendAndWaitForTransaction(contracts.redemptionHelper.setAddresses(
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.troveManager.address,
        contracts.collateralConfig.address,
        oathAddress,
        contracts.priceFeed.address,
        contracts.lusdToken.address,
        contracts.sortedTroves.address,
        LQTYContracts.lqtyStaking.address,
  {gasPrice}
      ))

    // set contracts in LiquidationHelper
    await this.isOwnershipRenounced(contracts.liquidationHelper) ||
      await this.sendAndWaitForTransaction(contracts.liquidationHelper.setAddresses(
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.troveManager.address,
        contracts.collateralConfig.address,
        contracts.stabilityPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeed.address,
        contracts.sortedTroves.address,
  {gasPrice}
      ))

    // set contracts in BorrowerOperations 
    await this.isOwnershipRenounced(contracts.borrowerOperations) ||
      await this.sendAndWaitForTransaction(contracts.borrowerOperations.setAddresses(
        contracts.collateralConfig.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeed.address,
        contracts.sortedTroves.address,
        contracts.lusdToken.address,
        LQTYContracts.lqtyStaking.address,
        contracts.leverager.address,
	{gasPrice}
      ))

    // Ensure BorrowerOperations' owner is governanceAddress
    await this.isOwnerDesiredAddress(contracts.borrowerOperations, governanceAddress) ||
      await this.sendAndWaitForTransaction(contracts.borrowerOperations.transferOwnership(governanceAddress, {gasPrice}))

    // set contracts in the Pools
    await this.isOwnershipRenounced(contracts.stabilityPool) ||
      await this.sendAndWaitForTransaction(contracts.stabilityPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.collateralConfig.address,
        contracts.troveManager.address,
        contracts.liquidationHelper.address,
        contracts.activePool.address,
        contracts.lusdToken.address,
        contracts.sortedTroves.address,
        contracts.priceFeed.address,
        LQTYContracts.communityIssuance.address,
	{gasPrice}
      ))

    await this.isOwnershipRenounced(contracts.activePool) ||
      await this.sendAndWaitForTransaction(contracts.activePool.setAddresses(
        contracts.collateralConfig.address,
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.redemptionHelper.address,
        contracts.liquidationHelper.address,
        contracts.stabilityPool.address,
        contracts.defaultPool.address,
        contracts.collSurplusPool.address,
        treasuryAddress,
        collaterals.map(c => c.reaperVaultAddress),
	{gasPrice}
      ))

    await this.isOwnershipRenounced(contracts.defaultPool) ||
      await this.sendAndWaitForTransaction(contracts.defaultPool.setAddresses(
        contracts.collateralConfig.address,
        contracts.troveManager.address,
        contracts.activePool.address,
	{gasPrice}
      ))

    await this.isOwnershipRenounced(contracts.collSurplusPool) ||
      await this.sendAndWaitForTransaction(contracts.collSurplusPool.setAddresses(
        contracts.collateralConfig.address,
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.liquidationHelper.address,
        contracts.activePool.address,
	{gasPrice}
      ))

    // set contracts in HintHelpers
    await this.isOwnershipRenounced(contracts.hintHelpers) ||
      await this.sendAndWaitForTransaction(contracts.hintHelpers.setAddresses(
        contracts.collateralConfig.address,
        contracts.sortedTroves.address,
        contracts.troveManager.address,
	{gasPrice}
      ))

    await this.isOwnershipRenounced(contracts.leverager) ||
      await this.sendAndWaitForTransaction(contracts.leverager.setAddresses(
        contracts.borrowerOperations.address,
        contracts.collateralConfig.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.priceFeed.address,
        contracts.lusdToken.address,
        this.configParams.externalAddrs.SWAPPER,
  {gasPrice}
      ))

      await this.isOwnershipRenounced(contracts.leverager) ||
      await this.sendAndWaitForTransaction(contracts.leverager.setExchangeSettings(
        [
          this.configParams.externalAddrs.VELO_ROUTER,
          this.configParams.externalAddrs.BALANCER_VAULT,
          this.configParams.externalAddrs.UNI_V3_ROUTER
        ],
  {gasPrice}
      ))
  }

  async connectLQTYContractsMainnet(LQTYContracts) {
    const gasPrice = this.configParams.GAS_PRICE
    // no-op
  }

  async connectLQTYContractsToCoreMainnet(
    LQTYContracts,
    coreContracts,
    oathAddress,
    stakingTokenAddress,
    governanceAddress
  ) {
    const gasPrice = this.configParams.GAS_PRICE
    await this.isOwnershipRenounced(LQTYContracts.lqtyStaking) ||
      await this.sendAndWaitForTransaction(LQTYContracts.lqtyStaking.setAddresses(
        stakingTokenAddress,
        coreContracts.lusdToken.address,
        coreContracts.troveManager.address,
        coreContracts.redemptionHelper.address, 
        coreContracts.borrowerOperations.address,
        coreContracts.activePool.address,
        coreContracts.collateralConfig.address,
	{gasPrice}
      ))

    // Initialize CommunityIssuance
    await this.isInitialized(LQTYContracts.communityIssuance) ||
      await this.sendAndWaitForTransaction(LQTYContracts.communityIssuance.setAddresses(
        oathAddress,
        coreContracts.stabilityPool.address,
        {gasPrice}
      ))

    // Ensure CommunityIssuance's owner is governanceAddress
    await this.isOwnerDesiredAddress(LQTYContracts.communityIssuance, governanceAddress) ||
      await this.sendAndWaitForTransaction(LQTYContracts.communityIssuance.transferOwnership(governanceAddress, {gasPrice}))
  }

  async connectUnipoolMainnet(uniPool, LQTYContracts, LUSDWETHPairAddr, duration) {
    const gasPrice = this.configParams.GAS_PRICE
    await this.isOwnershipRenounced(uniPool) ||
      await this.sendAndWaitForTransaction(uniPool.setParams(LQTYContracts.lqtyToken.address, LUSDWETHPairAddr, duration, {gasPrice}))
  }

  // --- Verify on Ethrescan ---
  async verifyContract(name, deploymentState, constructorArguments=[]) {
    if (!deploymentState[name] || !deploymentState[name].address) {
      console.error(`  --> No deployment state for contract ${name}!!`)
      return
    }
    if (deploymentState[name].verification) {
      console.log(`Contract ${name} already verified`)
      return
    }

    try {
      await this.hre.run("verify:verify", {
        address: deploymentState[name].address,
        constructorArguments,
      })
    } catch (error) {
      // if it was already verified, it’s like a success, so let’s move forward and save it
      if (error.name != 'NomicLabsHardhatPluginError') {
        console.error(`Error verifying: ${error.name}`)
        console.error(error)
        return
      }
    }

    deploymentState[name].verification = `${this.configParams.ETHERSCAN_BASE_URL}/${deploymentState[name].address}#code`

    this.saveDeployment(deploymentState)
  }

  // --- Helpers ---

  async logContractObjects (contracts) {
    console.log(`Contract objects addresses:`)
    for ( const contractName of Object.keys(contracts)) {
      console.log(`${contractName}: ${contracts[contractName].address}`);
    }
  }
}

module.exports = MainnetDeploymentHelper

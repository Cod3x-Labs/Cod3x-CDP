const { UniswapV2Factory } = require("./ABIs/UniswapV2Factory.js")
const { UniswapV2Pair } = require("./ABIs/UniswapV2Pair.js")
const { UniswapV2Router02 } = require("./ABIs/UniswapV2Router02.js")
const { ChainlinkAggregatorV3Interface } = require("./ABIs/ChainlinkAggregatorV3Interface.js")
const { TestHelper: th, TimeValues: timeVals } = require("../utils/testHelpers.js")
const { dec } = th
const MainnetDeploymentHelper = require("../utils/mainnetDeploymentHelpers.js")
const toBigNum = ethers.BigNumber.from

async function mainnetDeploy(configParams) {
  const isTest = configParams.isTest
  if (!isTest) {
    const date = new Date()
    console.log(date.toUTCString())
  }

  const deployerWallet = (await ethers.getSigners())[0]
  // const account2Wallet = (await ethers.getSigners())[1]
  assert.equal(deployerWallet.address, configParams.liquityAddrs.DEPLOYER)
  // assert.equal(account2Wallet.address, configParams.beneficiaries.ACCOUNT_2)

  const mdh = new MainnetDeploymentHelper(configParams, deployerWallet)

  let deploymentState = {}
  if (!isTest) {
    console.log(`deployer address: ${deployerWallet.address}`)
    let deployerETHBalance = await ethers.provider.getBalance(deployerWallet.address)
    console.log(`deployerETHBalance before: ${deployerETHBalance}`)

    deploymentState = mdh.loadPreviousDeployment()
  }

  // Deploy core logic contracts
  const liquityCore = await mdh.deployLiquityCoreMainnet(
    configParams.externalAddrs.TELLOR_MASTER,
    configParams.liquityAddrs.GOVERNANCE,
    configParams.liquityAddrs.GUARDIAN,
    deploymentState
  )
  if (!isTest) await mdh.logContractObjects(liquityCore)

  // Deploy LQTY Contracts
  const LQTYContracts = await mdh.deployLQTYContractsMainnet(deploymentState)

  // Connect all core contracts up
  await mdh.connectCoreContractsMainnet(
    liquityCore,
    LQTYContracts,
    configParams.collaterals,
    configParams.liquityAddrs.GOVERNANCE,
    configParams.externalAddrs.OATH,
    configParams.liquityAddrs.TREASURY
  )
  await mdh.connectLQTYContractsMainnet(LQTYContracts)
  await mdh.connectLQTYContractsToCoreMainnet(
    LQTYContracts,
    liquityCore,
    configParams.externalAddrs.OATH,
    configParams.externalAddrs.STAKING_TOKEN,
    configParams.liquityAddrs.GOVERNANCE,
  )

  // Deploy a read-only multi-trove getter
  const multiTroveGetter = await mdh.deployMultiTroveGetterMainnet(liquityCore, deploymentState)

  // Log LQTY addresses
  if (!isTest) await mdh.logContractObjects(LQTYContracts)

  return { liquityCore, LQTYContracts }
}

module.exports = {
  mainnetDeploy
}

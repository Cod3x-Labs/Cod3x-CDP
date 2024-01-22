const { mainnetDeploy } = require('./mainnetDeployment.js')
const configParams = require("./deploymentParams.localForkUpgrade.js")

const IWethMinimal = [
  "function approve(address, uint256) external",
  "function deposit() external payable",
]

const ETH_WHALE = "0x4200000000000000000000000000000000000006"
//const TEST_DEPLOYER_PRIVATEKEY = '0xbbfbee4961061d506ffbb11dfea64eba16355cbf1d9c29613126ba7fec0aed5d'

async function upgrade(isTest) {
  configParams.isTest = isTest

  //const deployerWallet = new ethers.Wallet(TEST_DEPLOYER_PRIVATEKEY, ethers.provider)
  const deployerWallet = (await ethers.getSigners())[0]

  // Impersonate the whale (artificially assume control of its pk)
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [ETH_WHALE]
  })
  // console.log(`whale address from import: ${ETH_WHALE}`)

  // Get the ETH whale signer 
  const whale = await ethers.provider.getSigner(ETH_WHALE)
  // console.log(`whale addr : ${await whale.getAddress()}`)
  // console.log(`whale ETH balance: ${ await ethers.provider.getBalance(whale.getAddress())}`)

  // Send ETH to the deployer's address
  await whale.sendTransaction({
    to:  deployerWallet.address,
    value: ethers.utils.parseEther("20.0")
  })
  // Send ETH to the governance address
  await whale.sendTransaction({
    to:  configParams.liquityAddrs.GOVERNANCE,
    value: ethers.utils.parseEther("20.0")
  })

  const weth = new ethers.Contract(
    configParams.collaterals[1].address,
    IWethMinimal,
    whale
  )
  const wsteth = await ethers.getContractAt(
    "contracts/Dependencies/IERC20.sol:IERC20",
    "0x1f32b1c2345538c0c6f582fcb022739c4a194ebb",
    whale
  )
  const swapper = await ethers.getContractAt(
    "ISwapper",
    configParams.externalAddrs.SWAPPER,
    whale
  )
  // Swap WETH for wstETH
  await weth.deposit({ value: ethers.utils.parseEther("20") })
  await weth.approve(swapper.address, ethers.utils.parseEther("10"))
  await swapper.swapUniV3(
    weth.address,
    wsteth.address,
    ethers.utils.parseEther("10"),
    [0, 0],
    configParams.externalAddrs.UNI_V3_ROUTER
  )
  await wsteth.transfer((await ethers.getSigners())[1].address, ethers.utils.parseEther("1"))
  await wsteth.transfer(deployerWallet.address, await wsteth.balanceOf(ETH_WHALE))

  // Stop impersonating whale
  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [ETH_WHALE]
  })

  const { liquityCore, LQTYContracts } = await mainnetDeploy(configParams)

  const ExchangeType = {
    VeloSolid: 0,
    Bal:       1,
    UniV3:     2,
  }
  await liquityCore.leverager.setExchange(liquityCore.lusdToken.address, weth.address, ExchangeType.UniV3)
  await liquityCore.leverager.setExchange(weth.address, liquityCore.lusdToken.address, ExchangeType.UniV3)
  await liquityCore.leverager.setExchange(liquityCore.lusdToken.address, wsteth.address, ExchangeType.UniV3)
  await liquityCore.leverager.setExchange(wsteth.address, liquityCore.lusdToken.address, ExchangeType.UniV3)

  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [configParams.liquityAddrs.GOVERNANCE]
  })
  const governance = await ethers.provider.getSigner(configParams.liquityAddrs.GOVERNANCE)
  await liquityCore.lusdToken.connect(governance).upgradeProtocol(
    liquityCore.troveManager.address,
    liquityCore.stabilityPool.address,
    liquityCore.borrowerOperations.address
  )
  const ReaperVault = await ethers.getContractFactory("ReaperVaultV2Minimal", governance)
  const wstethVault = await ReaperVault.deploy(
    wsteth.address,
    "Ethos Reserve wstETH Vault",
    "ethos-wstETH",
  )
  await liquityCore.collateralConfig.connect(governance).addNewCollateral(
    wsteth.address,
    ethers.utils.parseEther("1.08"),
    ethers.utils.parseEther("1.2"),
    ethers.utils.parseEther("2000000"),
    97200,
    14400,
    wstethVault.address,
    "0x698B585CbC4407e2D54aa898B2600B53C68958f7",
    "0x1962cde2f19178fe2bb2229e78a6d386e6406979edc7b9a1966d89d83b3ebf2e"
  )
  await network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [configParams.liquityAddrs.GOVERNANCE]
  })

  return { liquityCore, LQTYContracts }
}

module.exports = {
  upgrade
}

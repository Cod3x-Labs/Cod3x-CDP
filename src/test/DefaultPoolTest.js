const testHelpers = require("../utils/testHelpers.js")
const CollateralConfig = artifacts.require("./CollateralConfig.sol")
const ActivePool = artifacts.require("./ActivePool.sol")
const DefaultPool = artifacts.require("./DefaultPool.sol")
const NonPayable = artifacts.require('NonPayable.sol')
const ERC20 = artifacts.require("ERC20Mock.sol");
const ReaperVaultV2 = artifacts.require("ReaperVaultV2Minimal.sol");

const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN

contract('DefaultPool', async accounts => {
  let collateralConfig
  let defaultPool
  let activePool
  let mockTroveManager
  let mockRedemptionHelper
  let mockLiquidationHelper
  let mockBorrowerOps
  let mockStabilityPool
  let mockCollSurplusPool
  let collateral
  let mockTreasury
  let mockPriceFeed

  let [owner] = accounts

  beforeEach('Deploy contracts', async () => {
    collateralConfig = await CollateralConfig.new()
    defaultPool = await DefaultPool.new()
    activePool = await ActivePool.new()
    mockTroveManager = await NonPayable.new()
    mockRedemptionHelper = await NonPayable.new()
    mockLiquidationHelper = await NonPayable.new()
    mockBorrowerOps = await NonPayable.new()
    mockStabilityPool = await NonPayable.new()
    mockCollSurplusPool = await NonPayable.new()
    mockTreasury = await NonPayable.new()
    mockPriceFeed = await NonPayable.new()

    collateral = await ERC20.new("Wrapped Ether", "wETH", 12, mockTreasury.address, 0);
    const vault = await ReaperVaultV2.new(collateral.address, "wETH Crypt", "rfwETH");

    await collateralConfig.initialize(
      [collateral.address],
      [toBN(dec(12, 17))], // MCR for WETH at 120%
      [toBN(dec(165, 16))], // CCR for WETH at 165%
      [ethers.constants.MaxUint256],
      [14400], // 4 hour Chainlink timeout
      [14400], // 4 hour Tellor timeouts
      activePool.address,
      mockPriceFeed.address,
    )
    await defaultPool.setAddresses(collateralConfig.address, mockTroveManager.address, activePool.address)
    await activePool.setAddresses(collateralConfig.address, mockBorrowerOps.address, mockTroveManager.address,
      mockRedemptionHelper.address, mockLiquidationHelper.address, mockStabilityPool.address, defaultPool.address,
      mockCollSurplusPool.address, mockTreasury.address, [vault.address]
    );
  })

  it('sendCollateralToActivePool(): fails if caller is not TroveManager', async () => {
    const amount = dec(1, 12)
    await th.assertRevert(defaultPool.sendCollateralToActivePool(collateral.address, amount, { from: owner }))
  })
})

contract('Reset chain state', async accounts => { })

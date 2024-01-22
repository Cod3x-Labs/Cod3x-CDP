const mainnetLocalForkUpgrade = require("../mainnetDeployment/mainnetLocalForkUpgrade.js")
const { TestHelper: th } = require("../utils/testHelpers.js")
const { dec, assertRevert } = th
const { ethers, network, assert } = require("hardhat")

const IERC20Minimal = [
  "function approve(address, uint256) external",
  "function balanceOf(address) external view returns (uint256)",
  "function transfer(address, uint256) external",
]

const contractIfForking = hre.network.config.forking ? contract.only : contract.skip

// Because this test is the only one to fork and simulate an upgrade as opposed to a fresh deployment,
// it requires a different hardhat configuration in order to run.
// To run this test, run the command:
// `npx hardhat test --config hardhat.config.mainnet-fork.js`
contractIfForking('Leverager', async accounts => {
  const [deployer, whale] = accounts
  let deployerWallet
  let whaleWallet

  let contracts
  let collateral

  const ZERO_ADDRESS = th.ZERO_ADDRESS

  beforeEach(async () => {
    // reset fork including external contracts
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: hre.network.config.forking.url,
            blockNumber: hre.network.config.forking.blockNumber,
          },
        },
      ],
    });
  
    const { liquityCore, LQTYContracts } = await mainnetLocalForkUpgrade.upgrade(true)
    contracts = liquityCore

    deployerWallet = (await ethers.getSigners())[0]
    collateral = new ethers.Contract(
      (await contracts.collateralConfig.collaterals(2)), // WSTETH
      IERC20Minimal,
      deployerWallet
    )

    await collateral.approve(contracts.leverager.address, ethers.constants.MaxUint256)
    await contracts.lusdToken.approve(contracts.leverager.address, ethers.constants.MaxUint256)

    whaleWallet = (await ethers.getSigners())[1]
    await collateral.connect(whaleWallet).approve(contracts.borrowerOperations.address, ethers.constants.MaxUint256)
  })
  
  it('Levers up with 1 iteration', async () => {
    const ethPrice = await contracts.priceFeed.callStatic.fetchPrice(collateral.address)
    const collAmount = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethPrice)
    await contracts.leverager.leverToTargetCRWithNIterations(
      collateral.address,
      ethers.utils.parseEther("1.3"),
      1,
      collAmount,
      ethers.utils.parseEther("0.005"),
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      ethers.utils.parseEther("0.993"),
      ethers.utils.parseEther("0.99")
    )

    const status = await contracts.troveManager.getTroveStatus(deployer, collateral.address)
    assert.equal(status, 1)

    const ernBalance = await contracts.lusdToken.balanceOf(deployer)
    const collValue = (await contracts.troveManager.getTroveColl(deployer, collateral.address))
      .mul(ethPrice).div(ethers.utils.parseEther("1"))
    const debt = await contracts.troveManager.getTroveDebt(deployer, collateral.address)
    th.assertIsApproximatelyEqual(ernBalance, ethers.utils.parseEther("755.4346154"), Number(dec(1, 12)))
    th.assertIsApproximatelyEqual(collValue, ethers.utils.parseEther("1000"), Number(dec(1, 17)))
    th.assertIsApproximatelyEqual(debt, ethers.utils.parseEther("769.2307692"), Number(dec(1, 17)))
  })

  it('Levers up with 2 iterations', async () => {
    const ethPrice = await contracts.priceFeed.callStatic.fetchPrice(collateral.address)
    const collAmount = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethPrice)
    await contracts.leverager.leverToTargetCRWithNIterations(
      collateral.address,
      ethers.utils.parseEther("1.3"),
      2,
      collAmount,
      ethers.utils.parseEther("0.005"),
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      ethers.utils.parseEther("0.993"),
      ethers.utils.parseEther("0.99")
    )

    const status = await contracts.troveManager.getTroveStatus(deployer, collateral.address)
    assert.equal(status, 1)

    assert.equal(await collateral.balanceOf(contracts.leverager.address), 0)
    assert.equal(await contracts.lusdToken.balanceOf(contracts.leverager.address), 0)

    const ernBalance = await contracts.lusdToken.balanceOf(deployer)
    const collValue = (await contracts.troveManager.getTroveColl(deployer, collateral.address))
      .mul(ethPrice).div(ethers.utils.parseEther("1"))
    const debt = await contracts.troveManager.getTroveDebt(deployer, collateral.address)
    th.assertIsApproximatelyEqual(ernBalance, ethers.utils.parseEther("578.0245731"), Number(dec(25, 18)))
    th.assertIsApproximatelyEqual(collValue, ethers.utils.parseEther("1755.207985"), Number(dec(25, 18)))
    th.assertIsApproximatelyEqual(debt, ethers.utils.parseEther("1350.159988"), Number(dec(25, 18)))
  })

  it('Delevers and closes from 1.3 CR max leverage', async () => {
    const ethPrice = await contracts.priceFeed.callStatic.fetchPrice(collateral.address)

    // need at least one other open trove in order to close
    await contracts.borrowerOperations.connect(whaleWallet).openTrove(
      collateral.address,
      ethers.utils.parseEther("1"),
      ethers.utils.parseEther("0.005"),
      ethers.utils.parseEther("100"),
      ZERO_ADDRESS,
      ZERO_ADDRESS
    )

    // lever up
    const collAmount = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethPrice)
    await contracts.leverager.leverToTargetCRWithNIterations(
      collateral.address,
      ethers.utils.parseEther("1.3"),
      15,
      collAmount,
      ethers.utils.parseEther("0.005"),
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      ethers.utils.parseEther("0.993"),
      ethers.utils.parseEther("0.99")
    )

    // mint more ERN to have enought to close trove (needed if small collAmount used on lever up)
    // const ernToMint = ethers.utils.parseEther("50")
    // const collAmount2 = ernToMint.mul(ethers.utils.parseEther("1.3")).div(ethPrice) // 1.3 CR
    // await contracts.borrowerOperations.adjustTrove(
    //   collateral.address,
    //   ethers.utils.parseEther("0.005"),
    //   collAmount2,
    //   0,
    //   ernToMint,
    //   true,
    //   ZERO_ADDRESS,
    //   ZERO_ADDRESS,
    //   ethers.utils.parseEther("1.03"),
    //   ethers.utils.parseEther("0.99")
    // )

    // delever
    const ernBalance = await contracts.lusdToken.balanceOf(deployer)
    const initialCollBal = await collateral.balanceOf(deployer)
    await contracts.leverager.deleverAndCloseTrove(
      collateral.address,
      ernBalance,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      ethers.utils.parseEther("0.993"),
      ethers.utils.parseEther("0.99")
    )

    const debt = await contracts.troveManager.getTroveDebt(deployer, collateral.address)
    assert.equal(debt, 0)

    const status = await contracts.troveManager.getTroveStatus(deployer, collateral.address)
    assert.equal(status, 2)

    assert.equal(await collateral.balanceOf(contracts.leverager.address), 0)
    assert.equal(await contracts.lusdToken.balanceOf(contracts.leverager.address), 0)

    const dollarValueRecovered = (await contracts.lusdToken.balanceOf(deployer)).mul(ethers.utils.parseEther("0.98686")).div(ethers.utils.parseEther("1"))
      .add((await collateral.balanceOf(deployer)).sub(initialCollBal).mul(ethPrice).div(ethers.utils.parseEther("1")))
    th.assertIsApproximatelyEqual(dollarValueRecovered, ethers.utils.parseEther("1000"), Number(dec(25, 18)))
  })

  it('Reverts with too many iterations', async () => {
    const collAmount = ethers.utils.parseEther("1")
    await assertRevert(contracts.leverager.leverToTargetCRWithNIterations(
      collateral.address,
      ethers.utils.parseEther("2"),
      16,
      collAmount,
      ethers.utils.parseEther("0.005"),
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      ethers.utils.parseEther("0.993"),
      ethers.utils.parseEther("0.99")
    ), "Leverager: Too many iterations")
  })
})

const NonPayable = artifacts.require("./NonPayable.sol")

const { expect } = require('chai');
const deploymentHelper = require("../utils/deploymentHelpers.js")

const { TestHelper: th } = require("../utils/testHelpers.js")
const { toBN, dec, assertRevert } = th

const TroveManagerTester = artifacts.require("./TroveManagerTester")

contract('CollateralConfig', async accounts => {
  const [owner, alice] = accounts

  let coreContracts
  let collateralConfig
  let collaterals
  let troveManager

  const openTrove = async (params) => th.openTrove(coreContracts, params)

  beforeEach(async () => {
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(996, 1000)

    coreContracts = await deploymentHelper.deployLiquityCore()
    coreContracts.troveManager = await TroveManagerTester.new()
    coreContracts = await deploymentHelper.deployLUSDTokenTester(coreContracts)
    coreContracts = await deploymentHelper.deployTestCollaterals(coreContracts)
    const LQTYContracts = await deploymentHelper.deployLQTYTesterContractsHardhat(bountyAddress, lpRewardsAddress, multisig)

    await deploymentHelper.connectLQTYContracts(LQTYContracts)
    await deploymentHelper.connectCoreContracts(coreContracts, LQTYContracts)
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, coreContracts)

    collateralConfig = coreContracts.collateralConfig
    collaterals = coreContracts.collaterals
    troveManager = coreContracts.troveManager
  });

  it('sets the right values on initializing', async () => {
    const allowedCollaterals = await collateralConfig.getAllowedCollaterals();
    const expectedAllowedCollaterals = collaterals.map(c => c.address);
    expect(allowedCollaterals).to.eql(expectedAllowedCollaterals);

    expect(await collateralConfig.isCollateralAllowed(collaterals[0].address)).to.be.true;
    expect(await collateralConfig.isCollateralAllowed(collaterals[1].address)).to.be.true;
    expect(await collateralConfig.isCollateralAllowed(accounts[0])).to.be.false;

    expect(await collateralConfig.getCollateralDecimals(collaterals[0].address)).to.eql(toBN('12'));
    expect(await collateralConfig.getCollateralDecimals(collaterals[1].address)).to.eql(toBN('8'));
    await th.assertRevert(
      collateralConfig.getCollateralDecimals(accounts[0]), "Invalid collateral address"
    );

    expect(await collateralConfig.getCollateralMCR(collaterals[0].address)).to.eql(toBN(dec(120, 16)));
    expect(await collateralConfig.getCollateralMCR(collaterals[1].address)).to.eql(toBN(dec(130, 16)));
    await th.assertRevert(
      collateralConfig.getCollateralMCR(accounts[0]), "Invalid collateral address"
    );

    expect(await collateralConfig.getCollateralCCR(collaterals[0].address)).to.eql(toBN(dec(165, 16)));
    expect(await collateralConfig.getCollateralCCR(collaterals[1].address)).to.eql(toBN(dec(180, 16)));
    await th.assertRevert(
      collateralConfig.getCollateralCCR(accounts[0]), "Invalid collateral address"
    );
  });

  it('can be initialized only once', async () => {
    await th.assertRevert(
      collateralConfig.initialize(
        collaterals.map(c => c.address),
        [toBN(dec(12, 17)), toBN(dec(13, 17))], // MCR for WETH at 120%, and for WBTC at 130%
        [toBN(dec(165, 16)), toBN(dec(18, 17))], // CCR for WETH at 165%, and for WBTC at 180%
        [ethers.constants.MaxUint256, ethers.constants.MaxUint256],
        [14400, 14400], // 4 hour Chainlink timeouts
        [14400, 14400], // 4 hour Tellor timeouts
        coreContracts.activePool.address,
        coreContracts.priceFeedTestnet.address,
      ),
      "Can only initialize once"
    );
  });

  it('owner can update CRs but only by lowering them', async () => {
    await th.assertRevert(
      collateralConfig.updateCollateralRatios(
        collaterals[0].address,
        toBN(dec(121, 16)),
        toBN(dec(165, 16))
      ),
      "Can only walk down the MCR"
    );

    await th.assertRevert(
      collateralConfig.updateCollateralRatios(
        collaterals[0].address,
        toBN(dec(120, 16)),
        toBN(dec(166, 16))
      ),
      "Can only walk down the CCR"
    );

    await th.assertRevert(
      collateralConfig.updateCollateralRatios(
        collaterals[0].address,
        toBN(dec(121, 16)),
        toBN(dec(166, 16))
      ),
      "Can only walk down the MCR"
    );

    await collateralConfig.updateCollateralRatios(
      collaterals[0].address,
      toBN(dec(115, 16)),
      toBN(dec(155, 16))
    );
    expect(await collateralConfig.getCollateralMCR(collaterals[0].address)).to.eql(toBN(dec(115, 16)));
    expect(await collateralConfig.getCollateralCCR(collaterals[0].address)).to.eql(toBN(dec(155, 16)));

    await th.assertRevert(
      collateralConfig.updateCollateralRatios(
        collaterals[0].address,
        toBN(dec(1004, 15)),
        toBN(dec(155, 16))
      ),
      "MCR below allowed minimum"
    );

    await th.assertRevert(
      collateralConfig.updateCollateralRatios(
        collaterals[0].address,
        toBN(dec(115, 16)),
        toBN(dec(1009, 15))
      ),
      "CCR below allowed minimum"
    );
  });

  it('debt limit is enforced', async () => {
    const LUSD_GAS_COMPENSATION = await troveManager.LUSD_GAS_COMPENSATION()
    const MIN_NET_DEBT = await troveManager.MIN_NET_DEBT()

    await collateralConfig.updateCollateralDebtLimit(
      collaterals[0].address,
      toBN(dec(200, 18)).add(LUSD_GAS_COMPENSATION)
    )

    await assertRevert(
      openTrove({
        collateral: collaterals[0],
        extraLUSDAmount: toBN(dec(201, 18)).sub(MIN_NET_DEBT),
        extraParams: { from: alice }
      }),
      "TroveManager: Debt increase exceeds limit"
    )

    await openTrove({
      collateral: collaterals[0],
      extraLUSDAmount: toBN(dec(199, 18)).sub(MIN_NET_DEBT),
      extraParams: { from: alice }
    })

    const troveDebt = await troveManager.getTroveDebt(alice, collaterals[0].address)
    th.assertIsApproximatelyEqual(troveDebt, toBN(dec(199, 18)).add(LUSD_GAS_COMPENSATION), Number(dec(1, 18)))
  })

  it('cannot add existing collateral', async () => {
    const mockChainlinkAggregator = await NonPayable.new()
    await assertRevert(
      collateralConfig.addNewCollateral(
        collaterals[0].address,
        toBN(dec(12, 17)),
        toBN(dec(165, 16)),
        ethers.constants.MaxUint256,
        14400,
        14400,
        coreContracts.reapervaults[1].address,
        mockChainlinkAggregator.address,
        "0x1",
      ),
      "collateral already allowed"
    )
  })
});

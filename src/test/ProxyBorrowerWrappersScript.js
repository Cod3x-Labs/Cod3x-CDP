const deploymentHelper = require("../utils/deploymentHelpers.js");
const testHelpers = require("../utils/testHelpers.js");

const TroveManagerTester = artifacts.require("TroveManagerTester");

const th = testHelpers.TestHelper;

const dec = th.dec;
const toBN = th.toBN;
const mv = testHelpers.MoneyValues;
const timeValues = testHelpers.TimeValues;

const assertRevert = th.assertRevert;

const GAS_PRICE = 10000000;

const {
  buildUserProxies,
  BorrowerOperationsProxy,
  BorrowerWrappersProxy,
  TroveManagerProxy,
  StabilityPoolProxy,
  SortedTrovesProxy,
  TokenProxy,
} = require("../utils/proxyHelpers.js");

contract("BorrowerWrappers", async (accounts) => {
  const [
    owner,
    alice,
    bob,
    carol,
    dennis,
    whale,
    A,
    B,
    C,
    D,
    E,
    defaulter_1,
    defaulter_2,
    // frontEnd_1, frontEnd_2, frontEnd_3
  ] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000);

  let priceFeed;
  let lusdToken;
  let sortedTroves;
  let troveManagerOriginal;
  let troveManager;
  let activePool;
  let stabilityPool;
  let defaultPool;
  let collSurplusPool;
  let borrowerOperations;
  let borrowerWrappers;

  let contracts;
  let collaterals;
  let communityIssuance;

  let LUSD_GAS_COMPENSATION;

  const getOpenTroveLUSDAmount = async (totalDebt) =>
    th.getOpenTroveLUSDAmount(contracts, totalDebt);
  const getActualDebtFromComposite = async (compositeDebt) =>
    th.getActualDebtFromComposite(compositeDebt, contracts);
  const getNetBorrowingAmount = async (debtWithFee) =>
    th.getNetBorrowingAmount(contracts, debtWithFee);
  const openTrove = async (params) => th.openTrove(contracts, params);

  beforeEach(async () => {
    contracts = await deploymentHelper.deployTestCollaterals(
      await deploymentHelper.deployLiquityCore(),
    );
    contracts.troveManager = await TroveManagerTester.new();
    contracts = await deploymentHelper.deployLUSDToken(contracts);
    const LQTYContracts =
      await deploymentHelper.deployLQTYTesterContractsHardhat(multisig);

    await deploymentHelper.connectLQTYContracts(LQTYContracts);
    await deploymentHelper.connectCoreContracts(contracts, LQTYContracts);
    await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts);

    troveManagerOriginal = contracts.troveManager;

    const users = [
      alice,
      bob,
      carol,
      dennis,
      whale,
      A,
      B,
      C,
      D,
      E,
      defaulter_1,
      defaulter_2,
    ];
    await deploymentHelper.deployProxyScripts(
      contracts,
      LQTYContracts,
      owner,
      users,
    );

    priceFeed = contracts.priceFeedTestnet;
    lusdToken = contracts.lusdToken;
    sortedTroves = contracts.sortedTroves;
    troveManager = contracts.troveManager;
    activePool = contracts.activePool;
    stabilityPool = contracts.stabilityPool;
    defaultPool = contracts.defaultPool;
    collSurplusPool = contracts.collSurplusPool;
    borrowerOperations = contracts.borrowerOperations;
    borrowerWrappers = contracts.borrowerWrappers;
    communityIssuance = LQTYContracts.communityIssuance;
    collaterals = contracts.collaterals;

    LUSD_GAS_COMPENSATION = await borrowerOperations.LUSD_GAS_COMPENSATION();
  });

  it("proxy owner can recover ERC20", async () => {
    const collDecimals = await contracts.collateralConfig.getCollateralDecimals(
      collaterals[0].address,
    );
    const amount = toBN(dec(1, collDecimals));
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);

    // send some tokens to proxy
    await collaterals[0].mint(owner, amount);
    await collaterals[0].transferInternal(owner, proxyAddress, amount);
    assert.equal(
      await collaterals[0].balanceOf(proxyAddress),
      amount.toString(),
    );

    const balanceBefore = toBN(await collaterals[0].balanceOf(alice));

    // recover tokens
    await borrowerWrappers.transferERC20(
      collaterals[0].address,
      alice,
      amount,
      { from: alice },
    );

    const balanceAfter = toBN(await collaterals[0].balanceOf(alice));
    assert.equal(balanceAfter.sub(balanceBefore), amount.toString());
  });

  it("non proxy owner cannot recover ERC20", async () => {
    const collDecimals = await contracts.collateralConfig.getCollateralDecimals(
      collaterals[0].address,
    );
    const amount = toBN(dec(1, collDecimals));
    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);

    // send some tokens to proxy
    await collaterals[0].mint(owner, amount);
    await collaterals[0].transferInternal(owner, proxyAddress, amount);
    assert.equal(
      await collaterals[0].balanceOf(proxyAddress),
      amount.toString(),
    );

    const balanceBefore = toBN(await collaterals[0].balanceOf(alice));

    // try to recover tokens
    const proxy = borrowerWrappers.getProxyFromUser(alice);
    const signature = "transferERC20(address,address,uint256)";
    const calldata = th.getTransactionData(signature, [alice, amount]);
    await assertRevert(
      proxy.methods["execute(address,bytes)"](
        borrowerWrappers.scriptAddress,
        calldata,
        { from: bob },
      ),
      "ds-auth-unauthorized",
    );

    assert.equal(
      await collaterals[0].balanceOf(proxyAddress),
      amount.toString(),
    );

    const balanceAfter = toBN(await collaterals[0].balanceOf(alice));
    assert.equal(balanceAfter, balanceBefore.toString());
  });

  // --- claimCollateralAndOpenTrove ---

  it("claimCollateralAndOpenTrove(): reverts if nothing to claim", async () => {
    // Whale opens Trove
    await openTrove({
      collateral: collaterals[0],
      ICR: toBN(dec(2, 18)),
      extraParams: { from: whale },
    });

    // alice opens Trove
    const { lusdAmount, collateral } = await openTrove({
      collateral: collaterals[0],
      ICR: toBN(dec(15, 17)),
      extraParams: { from: alice },
    });

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");

    // skip bootstrapping phase
    await th.fastForwardTime(
      timeValues.SECONDS_IN_ONE_WEEK * 2,
      web3.currentProvider,
    );

    // alice claims collateral and re-opens the trove
    await assertRevert(
      borrowerWrappers.claimCollateralAndOpenTrove(
        collaterals[0].address,
        0,
        th._100pct,
        lusdAmount,
        alice,
        alice,
        { from: alice },
      ),
      "CollSurplusPool: No collateral available to claim",
    );

    // check everything remain the same
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");
    th.assertIsApproximatelyEqual(
      await collSurplusPool.getUserCollateral(
        proxyAddress,
        collaterals[0].address,
      ),
      "0",
    );
    th.assertIsApproximatelyEqual(
      await lusdToken.balanceOf(proxyAddress),
      lusdAmount,
    );
    assert.equal(
      await troveManager.getTroveStatus(proxyAddress, collaterals[0].address),
      1,
    );
    th.assertIsApproximatelyEqual(
      await troveManager.getTroveColl(proxyAddress, collaterals[0].address),
      collateral,
    );
  });

  it("claimCollateralAndOpenTrove(): without sending any value", async () => {
    // alice opens Trove
    const {
      lusdAmount,
      netDebt: redeemAmount,
      collateral,
    } = await openTrove({
      collateral: collaterals[0],
      extraLUSDAmount: 0,
      ICR: toBN(dec(3, 18)),
      extraParams: { from: alice },
    });
    // Whale opens Trove
    await openTrove({
      collateral: collaterals[0],
      extraLUSDAmount: redeemAmount,
      ICR: toBN(dec(5, 18)),
      extraParams: { from: whale },
    });

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");

    // skip bootstrapping phase
    await th.fastForwardTime(
      timeValues.SECONDS_IN_ONE_WEEK * 2,
      web3.currentProvider,
    );

    // whale redeems 150 LUSD
    await th.redeemCollateral(
      whale,
      collaterals[0].address,
      contracts,
      redeemAmount,
      GAS_PRICE,
    );
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice(collaterals[0].address);
    const collDecimals = await contracts.collateralConfig.getCollateralDecimals(
      collaterals[0].address,
    );
    const expectedSurplus = collateral.sub(
      redeemAmount.mul(toBN(10).pow(collDecimals)).div(price),
    );
    th.assertIsApproximatelyEqual(
      await collSurplusPool.getUserCollateral(
        proxyAddress,
        collaterals[0].address,
      ),
      expectedSurplus,
    );
    assert.equal(
      await troveManager.getTroveStatus(proxyAddress, collaterals[0].address),
      4,
    ); // closed by redemption

    // alice claims collateral and re-opens the trove
    await borrowerWrappers.claimCollateralAndOpenTrove(
      collaterals[0].address,
      0,
      th._100pct,
      lusdAmount,
      alice,
      alice,
      { from: alice },
    );

    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");
    th.assertIsApproximatelyEqual(
      await collSurplusPool.getUserCollateral(
        proxyAddress,
        collaterals[0].address,
      ),
      "0",
    );
    th.assertIsApproximatelyEqual(
      await lusdToken.balanceOf(proxyAddress),
      lusdAmount.mul(toBN(2)),
    );
    assert.equal(
      await troveManager.getTroveStatus(proxyAddress, collaterals[0].address),
      1,
    );
    th.assertIsApproximatelyEqual(
      await troveManager.getTroveColl(proxyAddress, collaterals[0].address),
      expectedSurplus,
    );
  });

  it("claimCollateralAndOpenTrove(): sending value in the transaction", async () => {
    // alice opens Trove
    const {
      lusdAmount,
      netDebt: redeemAmount,
      collateral,
    } = await openTrove({
      collateral: collaterals[0],
      extraParams: { from: alice },
    });
    // Whale opens Trove
    await openTrove({
      collateral: collaterals[0],
      extraLUSDAmount: redeemAmount,
      ICR: toBN(dec(2, 18)),
      extraParams: { from: whale },
    });

    const proxyAddress = borrowerWrappers.getProxyAddressFromUser(alice);
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");

    // skip bootstrapping phase
    await th.fastForwardTime(
      timeValues.SECONDS_IN_ONE_WEEK * 2,
      web3.currentProvider,
    );

    // whale redeems 150 LUSD
    await th.redeemCollateral(
      whale,
      collaterals[0].address,
      contracts,
      redeemAmount,
      GAS_PRICE,
    );
    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");

    // surplus: 5 - 150/200
    const price = await priceFeed.getPrice(collaterals[0].address);
    const collDecimals = await contracts.collateralConfig.getCollateralDecimals(
      collaterals[0].address,
    );
    const expectedSurplus = collateral.sub(
      redeemAmount.mul(toBN(10).pow(collDecimals)).div(price),
    );
    th.assertIsApproximatelyEqual(
      await collSurplusPool.getUserCollateral(
        proxyAddress,
        collaterals[0].address,
      ),
      expectedSurplus,
    );
    assert.equal(
      await troveManager.getTroveStatus(proxyAddress, collaterals[0].address),
      4,
    ); // closed by redemption

    // alice claims collateral and re-opens the trove
    await collaterals[0].mint(alice, collateral);
    await collaterals[0].approveInternal(alice, proxyAddress, collateral);
    await borrowerWrappers.claimCollateralAndOpenTrove(
      collaterals[0].address,
      collateral,
      th._100pct,
      lusdAmount,
      alice,
      alice,
      { from: alice },
    );

    assert.equal(await collaterals[0].balanceOf(proxyAddress), "0");
    th.assertIsApproximatelyEqual(
      await collSurplusPool.getUserCollateral(
        proxyAddress,
        collaterals[0].address,
      ),
      "0",
    );
    th.assertIsApproximatelyEqual(
      await lusdToken.balanceOf(proxyAddress),
      lusdAmount.mul(toBN(2)),
    );
    assert.equal(
      await troveManager.getTroveStatus(proxyAddress, collaterals[0].address),
      1,
    );
    th.assertIsApproximatelyEqual(
      await troveManager.getTroveColl(proxyAddress, collaterals[0].address),
      expectedSurplus.add(collateral),
    );
  });
});

const CollateralConfig = artifacts.require("./CollateralConfig.sol");
const StabilityPool = artifacts.require("./StabilityPool.sol");
const TroveManager = artifacts.require("./TroveManager.sol");
const ActivePool = artifacts.require("./ActivePool.sol");
const DefaultPool = artifacts.require("./DefaultPool.sol");
const NonPayable = artifacts.require("./NonPayable.sol");
const ERC20 = artifacts.require("ERC20Mock.sol");
const ReaperVaultV2 = artifacts.require("ReaperVaultV2Minimal.sol");

const testHelpers = require("../utils/testHelpers.js");

const th = testHelpers.TestHelper;
const dec = th.dec;
const toBN = th.toBN;

const _minus_1_Ether = web3.utils.toWei("-1", "ether");

contract("StabilityPool", async (accounts) => {
  /* mock* are EOA’s, temporarily used to call protected functions.
  TODO: Replace with mock contracts, and later complete transactions from EOA
  */
  let stabilityPool;
  const [owner, alice] = accounts;

  beforeEach(async () => {
    stabilityPool = await StabilityPool.new();
    const dumbContractAddress = (await NonPayable.new()).address;
    await stabilityPool.setAddresses(
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
    );
  });

  it("getCollateral(): gets the recorded collateral balance", async () => {
    const collateral = "0x5b5e5CC89636CA2685b4e4f50E66099EBCFAb638"; // Arbitrary ERC20 address
    const recordedETHBalance = await stabilityPool.getCollateral(collateral);
    assert.equal(recordedETHBalance, 0);
  });

  it("getTotalLUSDDeposits(): gets the recorded LUSD balance", async () => {
    const recordedETHBalance = await stabilityPool.getTotalLUSDDeposits();
    assert.equal(recordedETHBalance, 0);
  });
});

contract("ActivePool", async (accounts) => {
  let activePool,
    mockBorrowerOperations,
    collateralConfig,
    troveManager,
    mockRedemptionHelper,
    mockLiquidationHelper;
  let collaterals, vaults;
  let treasury;
  let stabilityPool;

  const [owner, alice] = accounts;
  beforeEach(async () => {
    treasury = await NonPayable.new();
    const collateral1 = await ERC20.new(
      "Wrapped Ether",
      "wETH",
      12,
      treasury.address,
      0,
    ); // 12 decimal places
    const collateral2 = await ERC20.new(
      "Wrapped Bitcoin",
      "wBTC",
      8,
      treasury.address,
      0,
    ); // 8 decimal places
    const vault1 = await ReaperVaultV2.new(
      collateral1.address,
      "wETH Crypt",
      "rfwETH",
    );
    const vault2 = await ReaperVaultV2.new(
      collateral2.address,
      "wBTC Crypt",
      "rfwBTC",
    );
    collaterals = [collateral1, collateral2];
    vaults = [vault1, vault2];

    activePool = await ActivePool.new();
    collateralConfig = await CollateralConfig.new();
    troveManager = await TroveManager.new();
    mockRedemptionHelper = await NonPayable.new();
    mockLiquidationHelper = await NonPayable.new();
    mockBorrowerOperations = await NonPayable.new();
    stabilityPool = await StabilityPool.new();
    const dumbContractAddress = (await NonPayable.new()).address;
    await collateralConfig.initialize(
      [collateral1.address, collateral2.address],
      [toBN(dec(12, 17)), toBN(dec(13, 17))], // MCR for WETH at 120%, and for WBTC at 130%
      [toBN(dec(165, 16)), toBN(dec(18, 17))], // CCR for WETH at 165%, and for WBTC at 180%
      [ethers.MaxUint256, ethers.MaxUint256],
      [14400, 14400], // 4 hour Chainlink timeouts
      [14400, 14400], // 4 hour Tellor timeouts
      dumbContractAddress,
    );

    await troveManager.setAddresses(
      mockBorrowerOperations.address,
      collateralConfig.address,
      activePool.address,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      mockRedemptionHelper.address,
      mockLiquidationHelper.address,
    );

    await activePool.setAddresses(
      collateralConfig.address,
      mockBorrowerOperations.address,
      troveManager.address,
      mockRedemptionHelper.address,
      mockLiquidationHelper.address,
      stabilityPool.address,
      dumbContractAddress,
      dumbContractAddress,
    );

    await stabilityPool.setAddresses(
      dumbContractAddress,
      collateralConfig.address,
      troveManager.address,
      mockLiquidationHelper.address,
      activePool.address,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
      dumbContractAddress,
    );
  });

  it("getCollateral(): gets the recorded Collateral balance", async () => {
    const recordedCollateralBalance = await activePool.getCollateral(
      collaterals[0].address,
    );
    assert.equal(recordedCollateralBalance, 0);
  });

  it("getLUSDDebt(): gets the recorded LUSD balance", async () => {
    const recordedETHBalance = await activePool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedETHBalance, 0);
  });

  it("increaseLUSD(): increases the recorded LUSD balance by the correct amount", async () => {
    const recordedLUSD_balanceBefore = await activePool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceBefore, 0);

    // await activePool.increaseLUSDDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseLUSDDebtData = th.getTransactionData(
      "increaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx = await mockBorrowerOperations.forward(
      activePool.address,
      increaseLUSDDebtData,
    );
    assert.isTrue(tx.receipt.status);
    const recordedLUSD_balanceAfter = await activePool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceAfter, 100);
  });
  // Decrease
  it("decreaseLUSD(): decreases the recorded LUSD balance by the correct amount", async () => {
    // start the pool on 100 wei
    //await activePool.increaseLUSDDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseLUSDDebtData = th.getTransactionData(
      "increaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx1 = await mockBorrowerOperations.forward(
      activePool.address,
      increaseLUSDDebtData,
    );
    assert.isTrue(tx1.receipt.status);

    const recordedLUSD_balanceBefore = await activePool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceBefore, 100);

    //await activePool.decreaseLUSDDebt(100, { from: mockBorrowerOperationsAddress })
    const decreaseLUSDDebtData = th.getTransactionData(
      "decreaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx2 = await mockBorrowerOperations.forward(
      activePool.address,
      decreaseLUSDDebtData,
    );
    assert.isTrue(tx2.receipt.status);
    const recordedLUSD_balanceAfter = await activePool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceAfter, 0);
  });

  // send collateral
  it("sendCollateral(): decreases the recorded collateral balance by the correct amount", async () => {
    // setup: give pool 2 ether
    const activePool_initialBalance = await collaterals[0].balanceOf(
      activePool.address,
    );
    assert.equal(activePool_initialBalance, 0);
    // start pool with 2 ether
    //await web3.eth.sendTransaction({ from: mockBorrowerOperationsAddress, to: activePool.address, value: dec(2, 'ether') })
    await collaterals[0].mint(mockBorrowerOperations.address, dec(2, "ether"));
    await collaterals[0].approveInternal(
      mockBorrowerOperations.address,
      activePool.address,
      dec(2, "ether"),
    );
    const pullCollData = th.getTransactionData(
      "pullCollateralFromBorrowerOperationsOrDefaultPool(address,uint256)",
      [collaterals[0].address, web3.utils.toHex(dec(2, "ether"))],
    );
    const tx1 = await mockBorrowerOperations.forward(
      activePool.address,
      pullCollData,
    );
    assert.isTrue(tx1.receipt.status);

    const activePool_BalanceBeforeTx = await collaterals[0].balanceOf(
      activePool.address,
    );
    const alice_Balance_BeforeTx = await collaterals[0].balanceOf(alice);

    assert.equal(activePool_BalanceBeforeTx, dec(2, "ether"));

    // send collateral from pool to alice
    //await activePool.sendETH(alice, dec(1, 'ether'), { from: mockBorrowerOperationsAddress })
    const sendCollData = th.getTransactionData(
      "sendCollateral(address,address,uint256)",
      [collaterals[0].address, alice, web3.utils.toHex(dec(1, "ether"))],
    );
    const tx2 = await mockBorrowerOperations.forward(
      activePool.address,
      sendCollData,
      { from: owner },
    );
    assert.isTrue(tx2.receipt.status);

    const activePool_BalanceAfterTx = await collaterals[0].balanceOf(
      activePool.address,
    );
    const alice_Balance_AfterTx = await collaterals[0].balanceOf(alice);

    const alice_BalanceChange = alice_Balance_AfterTx.sub(
      alice_Balance_BeforeTx,
    );
    const pool_BalanceChange = activePool_BalanceAfterTx.sub(
      activePool_BalanceBeforeTx,
    );
    assert.equal(alice_BalanceChange, dec(1, "ether"));
    assert.equal(pool_BalanceChange, _minus_1_Ether);
  });

  it("sendCollateral works with default values, vault share bal is 0 before and after", async () => {
    // start pool with 2 ether
    await collaterals[0].mint(mockBorrowerOperations.address, dec(2, "ether"));
    await collaterals[0].approveInternal(
      mockBorrowerOperations.address,
      activePool.address,
      dec(2, "ether"),
    );
    const pullCollData = th.getTransactionData(
      "pullCollateralFromBorrowerOperationsOrDefaultPool(address,uint256)",
      [collaterals[0].address, web3.utils.toHex(dec(2, "ether"))],
    );
    await mockBorrowerOperations.forward(activePool.address, pullCollData);

    const activePool_CollBalBefore = await collaterals[0].balanceOf(
      activePool.address,
    );
    const alice_CollBalBefore = await collaterals[0].balanceOf(alice);
    const activePool_VaultBalBefore = await vaults[0].balanceOf(
      activePool.address,
    );

    assert.equal(activePool_CollBalBefore, dec(2, "ether"));
    assert.equal(activePool_VaultBalBefore, 0);

    // send 1 ether to alice
    const sendCollData = th.getTransactionData(
      "sendCollateral(address,address,uint256)",
      [collaterals[0].address, alice, web3.utils.toHex(dec(1, "ether"))],
    );
    await mockBorrowerOperations.forward(activePool.address, sendCollData, {
      from: owner,
    });

    const activePool_CollBalAfter = await collaterals[0].balanceOf(
      activePool.address,
    );
    const alice_CollBalAfter = await collaterals[0].balanceOf(alice);
    const activePool_VaultBalAfter = await vaults[0].balanceOf(
      activePool.address,
    );

    assert.equal(activePool_CollBalAfter, dec(1, "ether"));
    assert.equal(activePool_VaultBalAfter, 0);
    assert.equal(alice_CollBalAfter.sub(alice_CollBalBefore), dec(1, "ether"));
  });

  it("pullCollateral works with default values, vault share bal is 0 before and after", async () => {
    // start pool with 2 ether
    await collaterals[0].mint(mockBorrowerOperations.address, dec(2, "ether"));
    await collaterals[0].approveInternal(
      mockBorrowerOperations.address,
      activePool.address,
      dec(2, "ether"),
    );
    const pullCollData = th.getTransactionData(
      "pullCollateralFromBorrowerOperationsOrDefaultPool(address,uint256)",
      [collaterals[0].address, web3.utils.toHex(dec(2, "ether"))],
    );
    await mockBorrowerOperations.forward(activePool.address, pullCollData);

    const activePool_CollBalBefore = await collaterals[0].balanceOf(
      activePool.address,
    );
    const activePool_VaultBalBefore = await vaults[0].balanceOf(
      activePool.address,
    );

    assert.equal(activePool_CollBalBefore, dec(2, "ether"));
    assert.equal(activePool_VaultBalBefore, 0);

    // pull some more collateral from borrower ops
    await collaterals[0].mint(mockBorrowerOperations.address, dec(3, "ether"));
    await collaterals[0].approveInternal(
      mockBorrowerOperations.address,
      activePool.address,
      dec(3, "ether"),
    );
    const pullCollData2 = th.getTransactionData(
      "pullCollateralFromBorrowerOperationsOrDefaultPool(address,uint256)",
      [collaterals[0].address, web3.utils.toHex(dec(3, "ether"))],
    );
    await mockBorrowerOperations.forward(activePool.address, pullCollData2);

    const activePool_CollBalAfter = await collaterals[0].balanceOf(
      activePool.address,
    );
    const activePool_VaultBalAfter = await vaults[0].balanceOf(
      activePool.address,
    );

    assert.equal(activePool_CollBalAfter, dec(5, "ether"));
    assert.equal(activePool_VaultBalAfter, 0);
  });

  const setReasonableDefaultStateForYielding = async () => {
    await activePool.setYieldingPercentage(collaterals[0].address, 5000, {
      from: owner,
    });
    await activePool.setYieldingPercentage(collaterals[1].address, 5000, {
      from: owner,
    });

    await activePool.setYieldClaimThreshold(collaterals[0].address, 10000, {
      from: owner,
    });
    await activePool.setYieldClaimThreshold(collaterals[1].address, 10000, {
      from: owner,
    });

    // start pool with 10 ether
    await collaterals[0].mint(mockBorrowerOperations.address, dec(10, "ether"));
    await collaterals[0].approveInternal(
      mockBorrowerOperations.address,
      activePool.address,
      dec(10, "ether"),
    );
    const pullCollData = th.getTransactionData(
      "pullCollateralFromBorrowerOperationsOrDefaultPool(address,uint256)",
      [collaterals[0].address, web3.utils.toHex(dec(10, "ether"))],
    );
    await mockBorrowerOperations.forward(activePool.address, pullCollData);
  };
});

contract("DefaultPool", async (accounts) => {
  let defaultPool, collateralConfig, mockTroveManager, mockActivePool;
  let collaterals;

  const [owner, alice] = accounts;
  before(async () => {
    const multisig = "0x5b5e5CC89636CA2685b4e4f50E66099EBCFAb638"; // Arbitrary address for the multisig, which is not tested in this file
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

    collaterals = [collateral1, collateral2];
  });

  beforeEach(async () => {
    defaultPool = await DefaultPool.new();
    collateralConfig = await CollateralConfig.new();
    mockTroveManager = await NonPayable.new();
    mockActivePool = await NonPayable.new();
    const mockPriceFeed = await NonPayable.new();
    await collateralConfig.initialize(
      collaterals.map((c) => c.address),
      [toBN(dec(12, 17)), toBN(dec(13, 17))], // MCR for WETH at 120%, and for WBTC at 130%
      [toBN(dec(165, 16)), toBN(dec(18, 17))], // CCR for WETH at 165%, and for WBTC at 180%
      [ethers.MaxUint256, ethers.MaxUint256],
      [14400, 14400], // 4 hour Chainlink timeouts
      [14400, 14400], // 4 hour Tellor timeouts
      mockPriceFeed.address,
    );
    await defaultPool.setAddresses(
      collateralConfig.address,
      mockTroveManager.address,
      mockActivePool.address,
    );
  });

  it("getCollateral(): gets the recorded collateral balance", async () => {
    const recordedCollateralBalance = await defaultPool.getCollateral(
      collaterals[0].address,
    );
    assert.equal(recordedCollateralBalance, 0);
  });

  it("getLUSDDebt(): gets the recorded LUSD balance", async () => {
    const recordedETHBalance = await defaultPool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedETHBalance, 0);
  });

  it("increaseLUSD(): increases the recorded LUSD balance by the correct amount", async () => {
    const recordedLUSD_balanceBefore = await defaultPool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceBefore, 0);

    // await defaultPool.increaseLUSDDebt(100, { from: mockBorrowerOperationsAddress })
    const increaseLUSDDebtData = th.getTransactionData(
      "increaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx = await mockTroveManager.forward(
      defaultPool.address,
      increaseLUSDDebtData,
    );
    assert.isTrue(tx.receipt.status);
    const recordedLUSD_balanceAfter = await defaultPool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceAfter, 100);
  });

  it("decreaseLUSD(): decreases the recorded LUSD balance by the correct amount", async () => {
    // start the pool on 100 wei
    //await defaultPool.increaseLUSDDebt(100, { from: mockTroveManagerAddress })
    const increaseLUSDDebtData = th.getTransactionData(
      "increaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx1 = await mockTroveManager.forward(
      defaultPool.address,
      increaseLUSDDebtData,
    );
    assert.isTrue(tx1.receipt.status);

    const recordedLUSD_balanceBefore = await defaultPool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceBefore, 100);

    //await defaultPool.decreaseLUSDDebt(100, { from: mockTroveManagerAddress })
    const decreaseLUSDDebtData = th.getTransactionData(
      "decreaseLUSDDebt(address,uint256)",
      [collaterals[0].address, "0x64"],
    );
    const tx2 = await mockTroveManager.forward(
      defaultPool.address,
      decreaseLUSDDebtData,
    );
    assert.isTrue(tx2.receipt.status);
    const recordedLUSD_balanceAfter = await defaultPool.getLUSDDebt(
      collaterals[0].address,
    );
    assert.equal(recordedLUSD_balanceAfter, 0);
  });
});

contract("Reset chain state", async (accounts) => {});

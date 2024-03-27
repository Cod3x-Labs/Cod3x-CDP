const CollateralConfig = artifacts.require("./CollateralConfig.sol");
const PriceFeed = artifacts.require("./PriceFeedTester.sol");
const PriceFeedTestnet = artifacts.require("./PriceFeedTestnet.sol");
const MockChainlink = artifacts.require("./MockAggregator.sol");
const MockTellor = artifacts.require("./MockTellor.sol");
const TellorCaller = artifacts.require("./TellorCaller.sol");
const ERC20 = artifacts.require("ERC20Mock.sol");
const ERC4626 = artifacts.require("ERC4626Mock.sol");
const NonPayable = artifacts.require("./NonPayable.sol");

const testHelpers = require("../utils/testHelpers.js");
const th = testHelpers.TestHelper;

const { dec, assertRevert, toBN } = th;

contract("PriceFeed", async (accounts) => {
  const [owner, alice] = accounts;
  let priceFeedTestnet;
  let priceFeed;
  let zeroAddressPriceFeed;
  let mockChainlink;
  let mockChainlink2;
  let tellorCaller;
  const multisig = "0x5b5e5CC89636CA2685b4e4f50E66099EBCFAb638"; // Arbitrary address for the multisig, which is not tested in this file
  let collateral1;
  let collateral2;
  let collateralConfig;
  let mockTellor;

  const setAddresses = async () => {
    await priceFeed.setAddresses(
      collateralConfig.address,
      [mockChainlink.address, mockChainlink2.address],
      tellorCaller.address,
      [
        "0x0000000000000000000000000000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000000000000000000000000000002",
      ],
      { from: owner },
    );
  };

  const setAssetsPerCollateralShare = async () => {
    //ERC4626 collateral support setup
    const assetsPerShare = 2;
    await collateral1.setAssetsPerShare(assetsPerShare);
    return assetsPerShare;
  };

  before(async () => {
    const wETHCollAsset = await ERC20.new(
      "Wrapped Ether",
      "wETH",
      12,
      multisig,
      0,
    ); // 12 decimal places
    const wBTCCollAsset = await ERC20.new(
      "Wrapped Bitcoin",
      "wBTC",
      8,
      multisig,
      0,
    ); // 8 decimal places

    collateral1 = await ERC4626.new(
      wETHCollAsset.address,
      "Vault Wrapped Ether",
      "vwETH",
    );
    collateral2 = await ERC4626.new(
      wBTCCollAsset.address,
      "Vault Wrapped Bitcoin",
      "vwBTC",
    );
    collateralConfig = await CollateralConfig.new();
    const mockPriceFeed = await NonPayable.new();
    CollateralConfig.setAsDeployed(collateralConfig);
    await collateralConfig.initialize(
      [collateral1.address, collateral2.address],
      [toBN(dec(12, 17)), toBN(dec(13, 17))], // MCR for WETH at 120%, and for WBTC at 130%
      [toBN(dec(165, 16)), toBN(dec(18, 17))], // CCR for WETH at 165%, and for WBTC at 180%
      [ethers.MaxUint256, ethers.MaxUint256],
      [14400, 14400], // 4 hour Chainlink timeouts
      [14400, 14400], // 4 hour Tellor timeouts
      mockPriceFeed.address,
    );
  });

  beforeEach(async () => {
    priceFeedTestnet = await PriceFeedTestnet.new();
    PriceFeedTestnet.setAsDeployed(priceFeedTestnet);

    priceFeed = await PriceFeed.new();
    PriceFeed.setAsDeployed(priceFeed);

    zeroAddressPriceFeed = await PriceFeed.new();
    PriceFeed.setAsDeployed(zeroAddressPriceFeed);

    mockChainlink = await MockChainlink.new();
    MockChainlink.setAsDeployed(mockChainlink);

    mockChainlink2 = await MockChainlink.new();
    MockChainlink.setAsDeployed(mockChainlink2);

    mockTellor = await MockTellor.new();
    MockTellor.setAsDeployed(mockTellor);

    tellorCaller = await TellorCaller.new(mockTellor.address);
    TellorCaller.setAsDeployed(tellorCaller);

    // Set Chainlink latest and prev round Id's to non-zero
    await mockChainlink.setLatestRoundId(3);
    await mockChainlink2.setLatestRoundId(3);

    //Set current and prev prices in both oracles
    await mockChainlink.setPrice(dec(100, 18));
    await mockChainlink2.setPrice(dec(200, 18));
    await mockTellor.setPrice(dec(100, 18));

    // Set mock price updateTimes in both oracles to very recent
    const now = await th.getLatestBlockTimestamp(web3);
    await mockChainlink.setUpdateTime(now);
    await mockChainlink2.setUpdateTime(now);
    await mockTellor.setUpdateTime(now - 60 * 25); // needs to be at least 20 minutes old
  });

  describe("PriceFeed internal testing contract", async (accounts) => {
    it("fetchPrice before setPrice should return the default price", async () => {
      const price = await priceFeedTestnet.getPrice(collateral1.address);
      assert.equal(price.toString(), "0");
    });
    it("should be able to fetchPrice after setPrice, output of former matching input of latter", async () => {
      await priceFeedTestnet.setPrice(collateral1.address, dec(100, 18));
      const price = await priceFeedTestnet.getPrice(collateral1.address);
      assert.equal(price, dec(100, 18));
    });
  });

  describe("Mainnet PriceFeed setup", async (accounts) => {
    it("fetchPrice should fail on contract with no CollateralConfig address set", async () => {
      let response;
      try {
        response = await zeroAddressPriceFeed.fetchPrice(collateral1.address);
      } catch (err) {
        assert.include(
          err.message,
          "Transaction reverted without a reason string",
        );
        assert.isUndefined(
          response,
          "response should not be defined because tx is expected to be reverted",
        );
      }
    });

    it("setAddresses should fail whe called by nonOwner", async () => {
      await assertRevert(
        priceFeed.setAddresses(
          collateralConfig.address,
          [mockChainlink.address, mockChainlink2.address],
          tellorCaller.address,
          [
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000000000000000000000000000002",
          ],
          { from: alice },
        ),
        "Ownable: caller is not the owner",
      );
    });

    it("setAddresses should fail after address has already been set", async () => {
      // Owner can successfully set any address
      const txOwner = await priceFeed.setAddresses(
        collateralConfig.address,
        [mockChainlink.address, mockChainlink2.address],
        tellorCaller.address,
        [
          "0x0000000000000000000000000000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000000000000000000000000000002",
        ],
        { from: owner },
      );
      assert.isTrue(txOwner.receipt.status);

      await assertRevert(
        priceFeed.setAddresses(
          collateralConfig.address,
          [mockChainlink.address, mockChainlink2.address],
          tellorCaller.address,
          [
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000000000000000000000000000002",
          ],
          { from: owner },
        ),
        "Ownable: caller is not the owner",
      );

      await assertRevert(
        priceFeed.setAddresses(
          collateralConfig.address,
          [mockChainlink.address, mockChainlink2.address],
          tellorCaller.address,
          [
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000000000000000000000000000002",
          ],
          { from: alice },
        ),
        "Ownable: caller is not the owner",
      );
    });
  });

  it("C1 Chainlink working: fetchPrice should return the correct price, taking into account the number of decimal digits on the aggregator", async () => {
    await setAddresses();
    //ERC4626 collateral support setup
    const assetsPerShare = 2;
    await collateral1.setAssetsPerShare(assetsPerShare);

    // Oracle price price is 10.00000000
    await mockChainlink.setDecimals(8);
    await mockChainlink.setPrice(dec(1, 9));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(5, 18));

    await priceFeed.fetchPrice(collateral1.address);
    let oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 10, with 18 digit precision
    assert.equal(oraclePrice, dec(10, 18));

    let fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(10, 18) * assetsPerShare);

    // Oracle price is 1e9
    await mockChainlink.setDecimals(0);
    await mockChainlink.setPrice(dec(1, 9));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(2, 27));
    await priceFeed.fetchPrice(collateral1.address);
    oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 1e9, with 18 digit precision
    assert.isTrue(oraclePrice.eq(toBN(dec(1, 27))));
    //ERC4626 collateral test
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1, 27) * assetsPerShare);

    // Oracle price is 0.0001
    await mockChainlink.setDecimals(18);
    await mockChainlink.setPrice(dec(1, 14));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(2, 14));
    await priceFeed.fetchPrice(collateral1.address);
    oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision
    assert.isTrue(oraclePrice.eq(toBN(dec(1, 14))));
    //ERC4626 collateral test
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1, 14) * assetsPerShare);

    // Oracle price is 1234.56789
    await mockChainlink.setDecimals(5);
    await mockChainlink.setPrice(dec(123456789));
    await priceFeed.setLastGoodPrice(
      collateral1.address,
      "1000000000000000000000",
    );
    await priceFeed.fetchPrice(collateral1.address);
    oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision
    assert.equal(oraclePrice, 1234567890000000000000);
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, 1234567890000000000000 * assetsPerShare);
    collateral1.resetAssetsPerShare();
  });

  // --- Chainlink breaks ---
  it("C1 Chainlink breaks, Tellor working: fetchPrice should return the correct Tellor price, taking into account Tellor's 18-digit granularity", async () => {
    let tellorUpdateTime = await th.getLatestBlockTimestamp(web3);
    tellorUpdateTime = tellorUpdateTime - 60 * 25; // needs to be at least 20 minutes old and greater than previous update time
    await setAddresses();
    //ERC4626 collateral support setup
    const assetsPerShare = await setAssetsPerCollateralShare();
    // --- Chainlink fails, system switches to Tellor ---
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    // Chainlink breaks with negative price
    await mockChainlink.setPrice("-5000");
    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted

    let price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    let fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);

    // Tellor price is 10 at 18-digit precision
    await mockTellor.setPrice(dec(10, 18));
    await mockTellor.setUpdateTime(tellorUpdateTime++); // needs to be at least 20 minutes old
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 10, with 18 digit precision
    assert.equal(price, dec(10, 18));
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(10, 18) * assetsPerShare);

    // Tellor price is 1e9 at 18-digit precision
    await mockTellor.setPrice(dec(1, 27));
    await mockTellor.setUpdateTime(tellorUpdateTime++); // needs to be at least 20 minutes old
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 1e9, with 18 digit precision
    assert.equal(price, dec(1, 27));
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1, 27) * assetsPerShare);

    // Tellor price is 0.0001 at 18-digit precision
    await mockTellor.setPrice(dec(1, 14));
    await mockTellor.setUpdateTime(tellorUpdateTime++); // needs to be at least 20 minutes old
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision

    assert.equal(price, dec(1, 14));
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1, 14) * assetsPerShare);

    // Tellor price is 1234.56789 at 18-digit precision
    await mockTellor.setPrice(dec(123456789, 13));
    await mockTellor.setUpdateTime(tellorUpdateTime++); // needs to be at least 20 minutes old
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 0.0001 with 18 digit precision
    assert.equal(price, "1234567890000000000000");
    fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, 1234567890000000000000 * assetsPerShare);
  });

  it("C1 Chainlink breaks, Tellor working: fetchPrice should return the correct Tellor price, taking into account TellorCaller's last saved timestamp", async () => {
    let tellorUpdateTime = await th.getLatestBlockTimestamp(web3);
    tellorUpdateTime = tellorUpdateTime - 60 * 25; // needs to be at least 20 minutes old and greater than previous update time
    await setAddresses();
    // --- Chainlink fails, system switches to Tellor ---
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    // Chainlink breaks with negative price
    await mockChainlink.setPrice("-5000");

    await mockTellor.setPrice(dec(100, 18));
    await mockTellor.setUpdateTime(tellorUpdateTime);
    await mockChainlink.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted

    let price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(100, 18));

    // Tellor timestamp is less than previous update time saved in Tellor Caller
    await mockTellor.setPrice(dec(101, 18));
    await mockTellor.setUpdateTime(tellorUpdateTime - 1);
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 100e18, previous Tellor price
    assert.equal(price, dec(100, 18));

    // Tellor timestamp is equal to previous update time saved in Tellor Caller
    await mockTellor.setPrice(dec(102, 18));
    await mockTellor.setUpdateTime(tellorUpdateTime);
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 100e18, previous Tellor price
    assert.equal(price, dec(100, 18));

    // Tellor timestamp is greater than previous update time saved in Tellor Caller
    await mockTellor.setPrice(dec(103, 18));
    await mockTellor.setUpdateTime(tellorUpdateTime + 1);
    await priceFeed.fetchPrice(collateral1.address);
    price = await priceFeed.lastGoodPrice(collateral1.address);
    // Check Liquity PriceFeed gives 103e18, updated Tellor price
    assert.equal(price, dec(103, 18));
  });

  it("C1 chainlinkWorking: Chainlink broken by zero latest roundId, Tellor working: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setLatestRoundId(0);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink broken by zero latest roundId, Tellor working: use Tellor price", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setLatestRoundId(0);

    const priceFetchTx = await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink broken by zero timestamp, Tellor working, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking:  Chainlink broken by zero timestamp, Tellor working, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink broken by future timestamp, Tellor working, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    const now = await th.getLatestBlockTimestamp(web3);
    const future = toBN(now).add(toBN("1000"));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setUpdateTime(future);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink broken by future timestamp, Tellor working, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    const now = await th.getLatestBlockTimestamp(web3);
    const future = toBN(now).add(toBN("1000"));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setUpdateTime(future);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink broken by negative price, Tellor working,  switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setPrice("-5000");

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink broken by negative price, Tellor working, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setPrice("-5000");

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink broken - decimals call reverted, Tellor working, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setDecimalsRevert();

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink broken - decimals call reverted, Tellor working, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setDecimalsRevert();

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink broken - latest round call reverted, Tellor working, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setLatestRevert();

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: latest round call reverted, Tellor working, return the Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));
    await mockChainlink.setLatestRevert();

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  // --- Chainlink timeout ---

  it("C1 chainlinkWorking: Chainlink frozen, Tellor working: switch to usingTellorChainlinkFrozen", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours
    const now = await th.getLatestBlockTimestamp(web3);

    // Tellor price is recent
    await mockTellor.setUpdateTime(now - 60 * 25);
    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "3"); // status 3: using Tellor, Chainlink frozen
  });

  it("C1 chainlinkWorking: Chainlink frozen, Tellor working: return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    // Tellor price is recent
    await mockTellor.setUpdateTime(now - 60 * 25);
    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink frozen, Tellor frozen: switch to usingTellorChainlinkFrozen", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "3"); // status 3: using Tellor, Chainlink frozen
  });

  it("C1 chainlinkWorking: Chainlink frozen, Tellor frozen: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink times out, Tellor broken by 0 price: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // Tellor breaks by 0 price
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "4"); // status 4: using Chainlink, Tellor untrusted
  });

  it("C1 chainlinkWorking: Chainlink times out, Tellor broken by 0 price: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(999, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);

    // Expect lastGoodPrice has not updated
    assert.equal(price, dec(999, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink is out of date by <3hrs: remain chainlinkWorking", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(1234, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(1000, 18));
    await th.fastForwardTime(10740, web3.currentProvider); // fast forward 2hrs 59 minutes

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink is out of date by <3hrs: return Chainklink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(1234, 8));
    await priceFeed.setLastGoodPrice(collateral1.address, dec(1000, 18));
    await th.fastForwardTime(10740, web3.currentProvider); // fast forward 2hrs 59 minutes

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(1234, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1234, 18) * assetsPerShare);
  });

  // --- Chainlink price deviation ---

  it("C1 chainlinkWorking: Chainlink price drop of >50%, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50%, return the Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    await priceFeed.fetchPrice(collateral1.address);

    let price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(203, 16));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(203, 16) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of 50%, remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(dec(1, 8)); // price drops to 1

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price drop of 50%, return the Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(dec(1, 8)); // price drops to 1

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(1, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of <50%, remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(dec(100000001)); // price drops to 1.00000001:  a drop of < 50% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price drop of <50%, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(100000001); // price drops to 1.00000001:  a drop of < 50% from previous

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(100000001, 10));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(100000001, 10) * assetsPerShare);
  });

  // Price increase
  it("C1 chainlinkWorking: Chainlink price increase of >100%, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(400000001); // price increases to 4.000000001: an increase of > 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink price increase of >100%, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(400000001); // price increases to 4.000000001: an increase of > 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(203, 16));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(203, 16) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price increase of 100%, remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(dec(4, 8)); // price increases to 4: an increase of 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price increase of 100%, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(dec(4, 8)); // price increases to 4: an increase of 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(4, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(4, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price increase of <100%, remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(399999999); // price increases to 3.99999999: an increase of < 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price increase of <100%,  return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(203, 16));
    await mockChainlink.setPrice(399999999); // price increases to 3.99999999: an increase of < 100% from previous

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(399999999, 10));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(399999999, 10) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price matches: remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous
    await mockTellor.setPrice(dec(999999, 12)); // Tellor price drops to same value (18 decimals)

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price matches: return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous
    await mockTellor.setPrice(dec(999999, 12)); // Tellor price drops to same value (at 18 decimals)

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(99999999, 10));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(99999999, 10) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price within 5% of Chainlink: remain chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(10499, 16)); // Tellor price drops to 104.99: price difference with new Chainlink price is now just under 5%

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor price within 5% of Chainlink: return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(10499, 16)); // Tellor price drops to 104.99: price difference with new Chainlink price is now just under 5%

    await priceFeed.fetchPrice(collateral1.address);
    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(100, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(100, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor live but not within 5% of Chainlink: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(105000001, 12)); // Tellor price drops to 105.000001: price difference with new Chainlink price is now > 5%

    await priceFeed.fetchPrice(collateral1.address);
    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor live but not within 5% of Chainlink: return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(2, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(105000001, 12)); // Tellor price drops to 105.000001: price difference with new Chainlink price is now > 5%

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(105000001, 12)); // return Tellor price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(105000001, 12) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor frozen: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(100, 18));

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider);

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    console.log(tellorUpdateTime);
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now);

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "1"); // status 1: using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor frozen: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(100, 8)); // price drops to 100: a drop of > 50% from previous
    await mockTellor.setPrice(dec(100, 18));

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider);

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(1200, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1200, 18) * assetsPerShare);
  });

  // --- Chainlink fails and Tellor is broken ---

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 price: switch to bothOracleSuspect", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 price
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "2"); // status 2: both oracles untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 price: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(1300, 18));

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 price
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(1200, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1200, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 timestamp: switch to bothOracleSuspect", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0);
    const priceFetchTx = await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "2"); // status 2: both oracles untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by invalid timestamp: switch to bothOracleSuspect", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return timestamp that's less than 20 minutes old
    const now = await th.getLatestBlockTimestamp(web3);
    await mockTellor.setUpdateTime(now - 60 * 10);
    const priceFetchTx = await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "2"); // status 2: both oracles untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by 0 timestamp: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(1300, 18));

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);
    let price = await priceFeed.lastGoodPrice(collateral1.address);

    assert.equal(price, dec(1200, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1200, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by future timestamp: Pricefeed switches to bothOracleSuspect", async () => {
    await setAddresses();
    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return 0 timestamp
    await mockTellor.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "2"); // status 2: both oracles untrusted
  });

  it("C1 chainlinkWorking: Chainlink price drop of >50% and Tellor is broken by future timestamp: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockTellor.setPrice(dec(1300, 18));

    // Make mock Chainlink price deviate too much
    await mockChainlink.setPrice(99999999); // price drops to 0.99999999: a drop of > 50% from previous

    // Make mock Tellor return a future timestamp
    const now = await th.getLatestBlockTimestamp(web3);
    const future = toBN(now).add(toBN("10000"));
    await mockTellor.setUpdateTime(future);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(1200, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(1200, 18) * assetsPerShare);
  });

  // -- Chainlink is working
  it("C1 chainlinkWorking: Chainlink is working and Tellor is working - remain on chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(102, 8));

    await mockTellor.setPrice(dec(103, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink is working and Tellor is working - return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(102, 8));

    await mockTellor.setPrice(dec(103, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(102, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(102, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink is working and Tellor freezes - remain on chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await priceFeed.setLastGoodPrice(collateral1.address, dec(101, 18));
    await mockChainlink.setPrice(dec(102, 8));
    await mockTellor.setPrice(dec(103, 18));

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider);

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now); // Chainlink's price is current

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "0"); // status 0: Chainlink working
  });

  it("C1 chainlinkWorking: Chainlink is working and Tellor freezes - return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(1200, 18));

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await priceFeed.setLastGoodPrice(collateral1.address, dec(101, 18));
    await mockChainlink.setPrice(dec(102, 8));

    await mockTellor.setPrice(dec(103, 18));

    // 4 hours pass with no Tellor updates
    await th.fastForwardTime(14400, web3.currentProvider);

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now); // Chainlink's price is current

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(102, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(102, 18) * assetsPerShare);
  });

  it("C1 chainlinkWorking: Chainlink is working and Tellor breaks: switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setLastGoodPrice(collateral1.address, dec(101, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(102, 8));

    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const statusAfter = await priceFeed.status(collateral1.address);
    assert.equal(statusAfter, "4"); // status 4: Using Tellor, Chainlink untrusted
  });

  it("C1 chainlinkWorking: Chainlink is working and Tellor breaks: return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setLastGoodPrice(collateral1.address, dec(101, 18)); // establish a "last good price" from the previous price fetch

    const statusBefore = await priceFeed.status(collateral1.address);
    assert.equal(statusBefore, "0"); // status 0: Chainlink working

    await mockChainlink.setPrice(dec(102, 8));
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(102, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(102, 18) * assetsPerShare);
  });

  // --- Case 2: Using Tellor ---

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero price: switch to bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrice(dec(999, 8));

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    const now = await th.getLatestBlockTimestamp(web3);
    await mockTellor.setUpdateTime(now - 60 * 25);
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero price: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status: using Tellor, Chainlink untrusted

    await mockChainlink.setPrice(dec(999, 8));

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    const now = await th.getLatestBlockTimestamp(web3);
    await mockTellor.setUpdateTime(now - 60 * 25);
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by call reverted: switch to bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(999, 18));

    await mockTellor.setRevertRequest();

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by call reverted: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status collateral1.address1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(999, 18));

    await mockTellor.setRevertRequest();

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  // Using Tellor, Tellor breaks
  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero timestamp: switch to bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(999, 18));

    await mockTellor.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C2 usingTellorChainlinkUntrusted: Tellor breaks by zero timestamp: return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(123, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(999, 18));

    await mockTellor.setUpdateTime(0);

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  // Using Tellor, Tellor freezes
  it("C2 usingTellorChainlinkUntrusted: Tellor freezes - remain usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrice(dec(999, 8));

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 1); // status 1: using Tellor, Chainlink untrusted
  });

  it("C2 usingTellorChainlinkUntrusted: Tellor freezes - return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockChainlink.setPrice(dec(999, 8));

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setUpdateTime(now);

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(246, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(246, 18) * assetsPerShare);
  });

  // Using Tellor, both Chainlink & Tellor go live

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and <= 5% price difference - switch to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice(dec(105, 8)); // price = 105: 5% difference from Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C2 usingTellorChainlinkUntrusted: chainlink aggregator address upgraded - switch to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    const mockChainlink_alt = await MockChainlink.new();
    MockChainlink.setAsDeployed(mockChainlink_alt);
    await mockChainlink_alt.setLatestRoundId(3);
    await mockChainlink_alt.setPrice(dec(105, 18));
    const now = await th.getLatestBlockTimestamp(web3);
    await mockChainlink_alt.setUpdateTime(now);

    const mockChainlink_alt_broken = await MockChainlink.new();
    MockChainlink.setAsDeployed(mockChainlink_alt_broken);

    // reverts if invalid coll address
    await assertRevert(
      priceFeed.updateChainlinkAggregator(
        accounts[0],
        mockChainlink_alt.address,
        { from: owner },
      ),
      "Invalid collateral address",
    );

    // reverts if invalid aggregator
    await assertRevert(
      priceFeed.updateChainlinkAggregator(
        collateral1.address,
        mockChainlink_alt_broken.address,
        { from: owner },
      ),
      "PriceFeed: Chainlink must be working and current",
    );

    // reverts if caller is not owner
    await assertRevert(
      priceFeed.updateChainlinkAggregator(
        collateral1.address,
        mockChainlink_alt.address,
        { from: alice },
      ),
      "PriceFeed: Chainlink must be working and current",
    );

    await priceFeed.updateChainlinkAggregator(
      collateral1.address,
      mockChainlink_alt.address,
      { from: owner },
    );

    await mockTellor.setPrice(dec(100, 18)); // price = 100

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and <= 5% price difference - return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice(dec(105, 8)); // price = 105: 5% difference from Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(105, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(105, 18) * assetsPerShare);
  });

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and > 5% price difference - remain usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice("10500000001"); // price = 105.00000001: > 5% difference from Tellor

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 1); // status 1: using Tellor, Chainlink untrusted
  });

  it("C2 usingTellorChainlinkUntrusted: both Tellor and Chainlink are live and > 5% price difference - return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 1); // status 1: using Tellor, Chainlink untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice("10500000001"); // price = 105.00000001: > 5% difference from Tellor

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(100, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(100, 18) * assetsPerShare);
  });

  // --- Case 3: Both Oracles suspect

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and > 5% price difference remain bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 2); // status 2: both oracles untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice("10500000001"); // price = 105.00000001: > 5% difference from Tellor

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and > 5% price difference, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 2); // status 2: both oracles untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice("10500000001"); // price = 105.00000001: > 5% difference from Tellor

    await priceFeed.fetchPrice(collateral1.address);

    const oraclePrice = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(oraclePrice, dec(50, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(50, 18) * assetsPerShare);
  });

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and <= 5% price difference, switch to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 2); // status 2: both oracles untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice(dec(105, 8)); // price = 105: 5% difference from Tellor

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C3 bothOraclesUntrusted: both Tellor and Chainlink are live and <= 5% price difference, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 2); // status collateral1.address2: both oracles untrusted

    await mockTellor.setPrice(dec(100, 18)); // price = 100
    await mockChainlink.setPrice(dec(105, 8)); // price = 105: 5% difference from Tellor

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(105, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(105, 18) * assetsPerShare);
  });

  // --- Case 4 ---
  it("C4 usingTellorChainlinkFrozen: when both Chainlink and Tellor break, switch to bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    // Both Chainlink and Tellor break with 0 price
    await mockChainlink.setPrice(0);
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when both Chainlink and Tellor break, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 2); // status 2: using tellor, chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    // Both Chainlink and Tellor break with 0 price
    await mockChainlink.setPrice(dec(0));
    await mockTellor.setPrice(dec(0));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(50, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(50, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor freezes, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status collateral1.address3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 1); // status 1: using Tellor, Chainlink untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor freezes, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(50, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(50, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor live, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 1); // status 1: using Tellor, Chainlink untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink breaks and Tellor live, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    // Chainlink breaks
    await mockChainlink.setPrice(dec(0));

    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with <5% price difference, switch back to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(998, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with <5% price difference, return Chainlink current price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(998, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(999, 18)); // Chainlink price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with >5% price difference, switch back to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 1); // status 1: Using Tellor, Chainlink untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with >5% price difference, return Chainlink current price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18)); // Tellor price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with similar price, switch back to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(998, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor is live with similar price, return Chainlink current price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(998, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(999, 18)); // Chainlink price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor breaks, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status 4: Using Chainlink, Tellor untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink is live and Tellor breaks, return Chainlink current price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(999, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor breaks, switch to usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // set tellor broken
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status 4: using Chainlink, Tellor untrusted
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor broken, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status collateral1.address3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // set tellor broken
    await mockTellor.setPrice(0);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(50, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(50, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor live, remain usingTellorChainlinkFrozen", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // set Tellor to current time
    await mockTellor.setUpdateTime(now - 60 * 25);

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 3); // status 3: using Tellor, Chainlink frozen
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor live, return Tellor price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // set Tellor to current time
    await mockTellor.setUpdateTime(now - 60 * 25);

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(123, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(123, 18) * assetsPerShare);
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor freezes, remain usingTellorChainlinkFrozen", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // check Tellor price timestamp is out of date by > 4 hours
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 3); // status 3: using Tellor, Chainlink frozen
  });

  it("C4 usingTellorChainlinkFrozen: when Chainlink still frozen and Tellor freezes, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 3); // status 3: using Tellor, Chainlink frozen

    await priceFeed.setLastGoodPrice(collateral1.address, dec(50, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    // check Tellor price timestamp is out of date by > 4 hours
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(50, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(50, 18) * assetsPerShare);
  });

  // --- Case 5 ---
  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price >5% - no status change", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(123, 18)); // Greater than 5% difference with chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status collateral1.address4: using Chainlink, Tellor untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price >5% - return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(123, 18)); // Greater than 5% difference with chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(999, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live and Tellor price within <5%, switch to chainlinkWorking", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(998, 18)); // within 5% of Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 0); // status 0: Chainlink working
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(998, 18)); // within 5% of Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(999, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(999, 18) * assetsPerShare);
  });

  // ---------

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor price not within 5%, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(998, 8));
    await mockTellor.setPrice(dec(123, 18)); // Tellor not close to current Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status 4: using Chainlink, Tellor untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(998, 8));
    await mockTellor.setPrice(dec(123, 18)); // Tellor not close to current Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(998, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(998, 18) * assetsPerShare);
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor price not within 5%, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(99, 8)); // >50% price drop from previous Chainlink price
    await mockTellor.setPrice(dec(123, 18)); // Tellor not close to current Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both Oracles untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous,  Tellor price not within 5%, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status collateral1.address4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(99, 8)); // >50% price drop from previous Chainlink price
    await mockTellor.setPrice(dec(123, 18)); // Tellor not close to current Chainlink

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(246, 18)); // last good price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(246, 18) * assetsPerShare);
  });

  // -------

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, and Tellor is frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setPrice(dec(998, 8));
    await mockChainlink.setUpdateTime(now); // Chainlink is current

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status 4: using Chainlink, Tellor untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, <50% price deviation from previous, Tellor is frozen, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(999, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setPrice(dec(998, 8));
    await mockChainlink.setUpdateTime(now); // Chainlink is current

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(998, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(998, 18) * assetsPerShare);
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor is frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(200, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setPrice(dec(99, 8)); // >50% price drop from previous Chainlink price
    await mockChainlink.setUpdateTime(now); // Chainlink is current

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both Oracles untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink is live, >50% price deviation from previous, Tellor is frozen, return Chainlink price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4:  using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(200, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // fast forward 4 hours

    // check Tellor price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const tellorUpdateTime = await mockTellor.getTimestampbyQueryIdandIndex(
      "0x0000000000000000000000000000000000000000000000000000000000000001",
      0,
    );
    assert.isTrue(tellorUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await mockChainlink.setPrice(dec(99, 8)); // > 50% price drop from previous Chainlink price
    await mockChainlink.setUpdateTime(now); // Chainlink is current

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(246, 18)); // last good price
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(246, 18) * assetsPerShare);
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink frozen, remain on usingChainlinkTellorUntrusted", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 4); // status 4: using Chainlink, Tellor untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink frozen, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status 4: using Chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(999, 8));

    await mockTellor.setPrice(dec(123, 18));

    await th.fastForwardTime(14400, web3.currentProvider); // Fast forward 4 hours

    // check Chainlink price timestamp is out of date by > 4 hours
    const now = await th.getLatestBlockTimestamp(web3);
    const chainlinkUpdateTime = (await mockChainlink.latestRoundData())[3];
    assert.isTrue(chainlinkUpdateTime.lt(toBN(now).sub(toBN(14400))));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(246, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(246, 18) * assetsPerShare);
  });

  it("C5 usingChainlinkTellorUntrusted: when Chainlink breaks too, switch to bothOraclesSuspect", async () => {
    await setAddresses();
    priceFeed.setStatus(collateral1.address, 4); // status 4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockChainlink.setUpdateTime(0); // Chainlink breaks by 0 timestamp

    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const status = await priceFeed.status(collateral1.address);
    assert.equal(status, 2); // status 2: both oracles untrusted
  });

  it("C5 usingChainlinkTellorUntrusted: Chainlink breaks too, return last good price", async () => {
    await setAddresses();
    const assetsPerShare = await setAssetsPerCollateralShare();
    priceFeed.setStatus(collateral1.address, 4); // status collateral1.address4: using chainlink, Tellor untrusted

    await priceFeed.setLastGoodPrice(collateral1.address, dec(246, 18));

    await mockChainlink.setPrice(dec(999, 8));
    await mockChainlink.setUpdateTime(0); // Chainlink breaks by 0 timestamp

    await mockTellor.setPrice(dec(123, 18));

    await priceFeed.fetchPrice(collateral1.address);

    const price = await priceFeed.lastGoodPrice(collateral1.address);
    assert.equal(price, dec(246, 18));
    const fetchedPrice = await priceFeed.fetchPrice.call(collateral1.address);
    assert.equal(fetchedPrice, dec(246, 18) * assetsPerShare);
  });
});

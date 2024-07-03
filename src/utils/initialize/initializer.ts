import {
  ActivePool,
  BorrowerOperations,
  CollSurplusPool,
  CollateralConfig,
  CommunityIssuance,
  DefaultPool,
  GasPool,
  HintHelpers,
  LUSDToken,
  Leverager,
  LiquidationHelper,
  PriceFeed,
  RedemptionHelper,
  RewarderManager,
  SortedTroves,
  StabilityPool,
  TellorCaller,
  TroveManager,
} from "../../typechain-types";
import {
  StablecoinContract,
  StablecoinOwnedContract,
  Collateral,
  ContractName,
} from "../deploy/types";
import { ethers } from "hardhat";
import { ContractTransactionResponse, Signer, BaseContract } from "ethers";

export class Initializer {
  private readonly gasPrice: number;
  private readonly txConfirmations: number;

  constructor(gasPrice: number, txConfirmations: number) {
    this.gasPrice = gasPrice;
    this.txConfirmations = txConfirmations;
  }

  public async connect(
    signer: Signer,
    contractsNameAddr: ReadonlyMap<ContractName, string>,
  ): Promise<ReadonlyMap<ContractName, StablecoinContract>> {
    const contracts = new Map<ContractName, StablecoinContract>();
    console.log(
      `connecting the contracts. Number of contracts: ${contractsNameAddr.size}`,
    );

    for (const [name, address] of contractsNameAddr) {
      const contractFactory = await ethers.getContractFactory(name);
      const contract = new ethers.Contract(
        address,
        contractFactory.interface,
        signer,
      ) as BaseContract;
      contracts.set(name, contract as StablecoinContract);
    }

    return contracts;
  }

  public async initialize(
    contracts: ReadonlyMap<string, StablecoinContract>,
    collaterals: ReadonlyArray<Collateral>,
    governanceAddress: string,
    oathAddress: string,
    treasuryAddress: string,
    swapperAddress: string,
    veloRouterAddress: string,
    balancerVaultAddress: string,
    uniV3RouterAddress: string,
  ): Promise<void> {
    const collateralConfig = contracts.get(
      "collateralConfig",
    ) as CollateralConfig;
    const priceFeed = contracts.get("priceFeed") as PriceFeed;
    const tellorCaller = contracts.get("tellorCaller") as TellorCaller;
    const sortedTroves = contracts.get("sortedTroves") as SortedTroves;
    const troveManager = contracts.get("troveManager") as TroveManager;
    const borrowerOperations = contracts.get(
      "borrowerOperations",
    ) as BorrowerOperations;
    const activePool = contracts.get("activePool") as ActivePool;
    const defaultPool = contracts.get("defaultPool") as DefaultPool;
    const gasPool = contracts.get("gasPool") as GasPool;
    const stabilityPool = contracts.get("stabilityPool") as StabilityPool;
    const collSurplusPool = contracts.get("collSurplusPool") as CollSurplusPool;
    const lusdToken = contracts.get("lusdToken") as LUSDToken;
    const rewarderManager = contracts.get("rewarderManager") as RewarderManager;
    const redemptionHelper = contracts.get(
      "redemptionHelper",
    ) as RedemptionHelper;
    const liquidationHelper = contracts.get(
      "liquidationHelper",
    ) as LiquidationHelper;
    const leverager = contracts.get("leverager") as Leverager;
    const communityIssuance = contracts.get(
      "communityIssuance",
    ) as CommunityIssuance;
    const hintHelpers = contracts.get("hintHelpers") as HintHelpers;

    await this.initializeCollateralConfig(
      collateralConfig,
      collaterals,
      priceFeed,
      governanceAddress,
    );

    await this.initializePriceFeed(
      priceFeed,
      collateralConfig,
      collaterals,
      tellorCaller,
      governanceAddress,
    );

    await this.initializeSortedTroves(
      sortedTroves,
      troveManager,
      borrowerOperations,
    );

    await this.initializeTroveManager(
      troveManager,
      sortedTroves,
      borrowerOperations,
      collateralConfig,
      activePool,
      defaultPool,
      gasPool,
      collSurplusPool,
      priceFeed,
      lusdToken,
      rewarderManager,
      redemptionHelper,
      liquidationHelper,
      oathAddress,
      governanceAddress,
    );

    await this.initializeRewarderManager(rewarderManager, troveManager);

    await this.initializeRedemptionHelper(
      redemptionHelper,
      activePool,
      defaultPool,
      collateralConfig,
      priceFeed,
      lusdToken,
      sortedTroves,
      troveManager,
      oathAddress,
      treasuryAddress,
    );

    await this.initializeLiquidationHelper(
      liquidationHelper,
      activePool,
      defaultPool,
      collateralConfig,
      priceFeed,
      stabilityPool,
      sortedTroves,
      troveManager,
      collSurplusPool,
    );

    await this.initializeBorrowerOperations(
      borrowerOperations,
      activePool,
      defaultPool,
      collateralConfig,
      priceFeed,
      gasPool,
      sortedTroves,
      troveManager,
      collSurplusPool,
      lusdToken,
      leverager,
      treasuryAddress,
      governanceAddress,
    );

    await this.initializeStabilityPool(
      stabilityPool,
      activePool,
      borrowerOperations,
      collateralConfig,
      priceFeed,
      sortedTroves,
      troveManager,
      liquidationHelper,
      lusdToken,
      communityIssuance,
    );

    await this.initializeActivePool(
      activePool,
      borrowerOperations,
      collateralConfig,
      troveManager,
      liquidationHelper,
      redemptionHelper,
      stabilityPool,
      defaultPool,
      collSurplusPool,
    );

    await this.initializeDefaultPool(
      defaultPool,
      collateralConfig,
      troveManager,
      activePool,
    );

    await this.initializeCollSurplusPool(
      collSurplusPool,
      collateralConfig,
      troveManager,
      activePool,
      borrowerOperations,
      liquidationHelper,
    );

    await this.initializeHintHelpers(
      hintHelpers,
      collateralConfig,
      troveManager,
      sortedTroves,
    );

    await this.initializeLeverager(
      leverager,
      collateralConfig,
      borrowerOperations,
      activePool,
      defaultPool,
      priceFeed,
      lusdToken,
      troveManager,
      swapperAddress,
      veloRouterAddress,
      balancerVaultAddress,
      uniV3RouterAddress,
    );

    await this.initializeCommunityIssuance(
      communityIssuance,
      stabilityPool,
      oathAddress,
      governanceAddress,
    );
  }

  private async initializeCollateralConfig(
    collateralConfig: CollateralConfig,
    collaterals: ReadonlyArray<Collateral>,
    priceFeed: PriceFeed,
    governanceAddress: string,
  ): Promise<void> {
    if (!(await collateralConfig.initialized())) {
      await this.sendTransaction(
        collateralConfig.initialize(
          collaterals.map((c: Collateral) => c.address),
          collaterals.map((c: Collateral) => ethers.parseEther(c.MCR)),
          collaterals.map((c: Collateral) => ethers.parseEther(c.CCR)),
          collaterals.map((c: Collateral) => c.limit),
          collaterals.map((c: Collateral) => c.chainlinkTimeoutSec),
          collaterals.map((c: Collateral) => c.tellorTimeoutSec),
          await priceFeed.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }

    if (!(await this.hasExpectedOwner(collateralConfig, governanceAddress))) {
      await this.sendTransaction(
        collateralConfig.transferOwnership(governanceAddress, {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async initializePriceFeed(
    priceFeed: PriceFeed,
    collateralConfig: CollateralConfig,
    collaterals: ReadonlyArray<Collateral>,
    tellorCaller: TellorCaller,
    governanceAddress: string,
  ): Promise<void> {
    if (!(await priceFeed.initialized())) {
      await this.sendTransaction(
        priceFeed.setAddresses(
          await collateralConfig.getAddress(),
          collaterals.map((c: Collateral) => c.chainlinkAggregatorAddress),
          await tellorCaller.getAddress(),
          collaterals.map((c: Collateral) => c.tellorQueryID),
          collaterals.map((c: Collateral) => c.maxPriceDeviation),
          { gasPrice: this.gasPrice },
        ),
      );
    }

    if (!(await this.hasExpectedOwner(priceFeed, governanceAddress))) {
      await this.sendTransaction(
        priceFeed.transferOwnership(governanceAddress, {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async initializeSortedTroves(
    sortedTroves: SortedTroves,
    troveManager: TroveManager,
    borrowerOperations: BorrowerOperations,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(sortedTroves))) {
      await this.sendTransaction(
        sortedTroves.setParams(
          await troveManager.getAddress(),
          await borrowerOperations.getAddress(),
          {
            gasPrice: this.gasPrice,
          },
        ),
      );
    }
  }

  private async initializeTroveManager(
    troveManager: TroveManager,
    sortedTroves: SortedTroves,
    borrowerOperations: BorrowerOperations,
    collateralConfig: CollateralConfig,
    activePool: ActivePool,
    defaultPool: DefaultPool,
    gasPool: GasPool,
    collSurplusPool: CollSurplusPool,
    priceFeed: PriceFeed,
    lusdToken: LUSDToken,
    rewarderManager: RewarderManager,
    redemptionHelper: RedemptionHelper,
    liquidationHelper: LiquidationHelper,
    oathAddress: string,
    governanceAddress: string,
  ): Promise<void> {
    if (!(await troveManager.initialized())) {
      await this.sendTransaction(
        troveManager.setAddresses(
          await borrowerOperations.getAddress(),
          await collateralConfig.getAddress(),
          await activePool.getAddress(),
          await defaultPool.getAddress(),
          await gasPool.getAddress(),
          await collSurplusPool.getAddress(),
          await priceFeed.getAddress(),
          await lusdToken.getAddress(),
          await sortedTroves.getAddress(),
          oathAddress,
          await rewarderManager.getAddress(),
          await redemptionHelper.getAddress(),
          await liquidationHelper.getAddress(),
          {
            gasPrice: this.gasPrice,
          },
        ),
      );
    }

    if (!(await this.hasExpectedOwner(troveManager, governanceAddress))) {
      await this.sendTransaction(
        troveManager.transferOwnership(governanceAddress, {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async initializeRewarderManager(
    rewarderManager: RewarderManager,
    troveManager: TroveManager,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(rewarderManager))) {
      await this.sendTransaction(
        rewarderManager.setAddresses(await troveManager.getAddress(), {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async initializeRedemptionHelper(
    redemptionHelper: RedemptionHelper,
    activePool: ActivePool,
    defaultPool: DefaultPool,
    collateralConfig: CollateralConfig,
    priceFeed: PriceFeed,
    lusdToken: LUSDToken,
    sortedTroves: SortedTroves,
    troveManager: TroveManager,
    oathAddress: string,
    treasuryAddress: string,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(redemptionHelper))) {
      await this.sendTransaction(
        redemptionHelper.setAddresses(
          await activePool.getAddress(),
          await defaultPool.getAddress(),
          await troveManager.getAddress(),
          await collateralConfig.getAddress(),
          oathAddress,
          await priceFeed.getAddress(),
          await lusdToken.getAddress(),
          await sortedTroves.getAddress(),
          treasuryAddress,
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeLiquidationHelper(
    liquidationHelper: LiquidationHelper,
    activePool: ActivePool,
    defaultPool: DefaultPool,
    collateralConfig: CollateralConfig,
    priceFeed: PriceFeed,
    stabilityPool: StabilityPool,
    sortedTroves: SortedTroves,
    troveManager: TroveManager,
    collSurplusPool: CollSurplusPool,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(liquidationHelper))) {
      await this.sendTransaction(
        liquidationHelper.setAddresses(
          await activePool.getAddress(),
          await defaultPool.getAddress(),
          await troveManager.getAddress(),
          await collateralConfig.getAddress(),
          await stabilityPool.getAddress(),
          await collSurplusPool.getAddress(),
          await priceFeed.getAddress(),
          await sortedTroves.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeBorrowerOperations(
    borrowerOperations: BorrowerOperations,
    activePool: ActivePool,
    defaultPool: DefaultPool,
    collateralConfig: CollateralConfig,
    priceFeed: PriceFeed,
    gasPool: GasPool,
    sortedTroves: SortedTroves,
    troveManager: TroveManager,
    collSurplusPool: CollSurplusPool,
    lusdToken: LUSDToken,
    leverager: Leverager,
    treasuryAddress: string,
    governanceAddress: string,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(borrowerOperations))) {
      await this.sendTransaction(
        borrowerOperations.setAddresses(
          await collateralConfig.getAddress(),
          await troveManager.getAddress(),
          await activePool.getAddress(),
          await defaultPool.getAddress(),
          await gasPool.getAddress(),
          await collSurplusPool.getAddress(),
          await priceFeed.getAddress(),
          await sortedTroves.getAddress(),
          await lusdToken.getAddress(),
          treasuryAddress,
          await leverager.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }

    if (!(await this.hasExpectedOwner(borrowerOperations, governanceAddress))) {
      await this.sendTransaction(
        borrowerOperations.transferOwnership(governanceAddress, {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async initializeStabilityPool(
    stabilityPool: StabilityPool,
    activePool: ActivePool,
    borrowerOperations: BorrowerOperations,
    collateralConfig: CollateralConfig,
    priceFeed: PriceFeed,
    sortedTroves: SortedTroves,
    troveManager: TroveManager,
    liquidationHelper: LiquidationHelper,
    lusdToken: LUSDToken,
    communityIssuance: CommunityIssuance,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(stabilityPool))) {
      await this.sendTransaction(
        stabilityPool.setAddresses(
          await borrowerOperations.getAddress(),
          await collateralConfig.getAddress(),
          await troveManager.getAddress(),
          await liquidationHelper.getAddress(),
          await activePool.getAddress(),
          await lusdToken.getAddress(),
          await sortedTroves.getAddress(),
          await priceFeed.getAddress(),
          await communityIssuance.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeActivePool(
    activePool: ActivePool,
    borrowerOperations: BorrowerOperations,
    collateralConfig: CollateralConfig,
    troveManager: TroveManager,
    liquidationHelper: LiquidationHelper,
    redemptionHelper: RedemptionHelper,
    stabilityPool: StabilityPool,
    defaultPool: DefaultPool,
    collSurplusPool: CollSurplusPool,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(activePool))) {
      await this.sendTransaction(
        activePool.setAddresses(
          await collateralConfig.getAddress(),
          await borrowerOperations.getAddress(),
          await troveManager.getAddress(),
          await redemptionHelper.getAddress(),
          await liquidationHelper.getAddress(),
          await stabilityPool.getAddress(),
          await defaultPool.getAddress(),
          await collSurplusPool.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeDefaultPool(
    defaultPool: DefaultPool,
    collateralConfig: CollateralConfig,
    troveManager: TroveManager,
    activePool: ActivePool,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(defaultPool))) {
      await this.sendTransaction(
        defaultPool.setAddresses(
          await collateralConfig.getAddress(),
          await troveManager.getAddress(),
          await activePool.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeCollSurplusPool(
    collSurplusPool: CollSurplusPool,
    collateralConfig: CollateralConfig,
    troveManager: TroveManager,
    activePool: ActivePool,
    borrowerOperations: BorrowerOperations,
    liquidationHelper: LiquidationHelper,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(collSurplusPool))) {
      await this.sendTransaction(
        collSurplusPool.setAddresses(
          await collateralConfig.getAddress(),
          await borrowerOperations.getAddress(),
          await troveManager.getAddress(),
          await liquidationHelper.getAddress(),
          await activePool.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeHintHelpers(
    hintHelpers: HintHelpers,
    collateralConfig: CollateralConfig,
    troveManager: TroveManager,
    sortedTroves: SortedTroves,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(hintHelpers))) {
      await this.sendTransaction(
        hintHelpers.setAddresses(
          await collateralConfig.getAddress(),
          await sortedTroves.getAddress(),
          await troveManager.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeLeverager(
    leverager: Leverager,
    collateralConfig: CollateralConfig,
    borrowerOperations: BorrowerOperations,
    activePool: ActivePool,
    defaultPool: DefaultPool,
    priceFeed: PriceFeed,
    lusdToken: LUSDToken,
    troveManager: TroveManager,
    swapperAddress: string,
    veloRouterAddress: string,
    balancerVaultAddress: string,
    uniV3RouterAddress: string,
  ): Promise<void> {
    if (!(await this.isOwnershipRenounced(leverager))) {
      await this.sendTransaction(
        leverager.setAddresses(
          await borrowerOperations.getAddress(),
          await collateralConfig.getAddress(),
          await troveManager.getAddress(),
          await activePool.getAddress(),
          await defaultPool.getAddress(),
          await priceFeed.getAddress(),
          await lusdToken.getAddress(),
          swapperAddress,
          { gasPrice: this.gasPrice },
        ),
      );

      await this.sendTransaction(
        leverager.setExchangeSettings(
          {
            veloRouter: veloRouterAddress,
            balVault: balancerVaultAddress,
            uniV3Router: uniV3RouterAddress,
          },
          { gasPrice: this.gasPrice },
        ),
      );
    }
  }

  private async initializeCommunityIssuance(
    communityIssuance: CommunityIssuance,
    stabilityPool: StabilityPool,
    oathAddress: string,
    governanceAddress: string,
  ): Promise<void> {
    if (!(await communityIssuance.initialized())) {
      await this.sendTransaction(
        communityIssuance.setAddresses(
          oathAddress,
          await stabilityPool.getAddress(),
          { gasPrice: this.gasPrice },
        ),
      );
    }

    if (!(await this.hasExpectedOwner(communityIssuance, governanceAddress))) {
      await this.sendTransaction(
        communityIssuance.transferOwnership(governanceAddress, {
          gasPrice: this.gasPrice,
        }),
      );
    }
  }

  private async sendTransaction(
    txPromise: Promise<ContractTransactionResponse>,
  ): Promise<void> {
    const tx = await txPromise;
    try {
      console.log("Waiting for transaction to be confirmed...");
      const receipt = await ethers.provider.waitForTransaction(
        tx.hash,
        this.txConfirmations,
      );
      if (receipt == null) {
        throw Error("failed to send transaction");
      }
      console.log(
        `Transaction confirmed in block ${receipt.blockNumber} with ${this.txConfirmations} confirmations.`,
      );
    } catch (error) {
      console.error("Error waiting for transaction:", error);
      throw error;
    }
  }

  private async hasExpectedOwner(
    contract: StablecoinOwnedContract,
    expectedOwnerAddress: string,
  ): Promise<boolean> {
    const owner = await contract.owner();
    return owner.toUpperCase() == expectedOwnerAddress.toUpperCase();
  }

  private async isOwnershipRenounced(
    contract: StablecoinOwnedContract,
  ): Promise<boolean> {
    const owner = await contract.owner();
    return owner == ethers.ZeroAddress;
  }
}

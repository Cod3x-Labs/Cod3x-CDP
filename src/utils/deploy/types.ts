import {
  ActivePool,
  CollateralConfig,
  PriceFeed,
  LUSDToken,
  SortedTroves,
  TroveManager,
  StabilityPool,
  GasPool,
  DefaultPool,
  CollSurplusPool,
  BorrowerOperations,
  HintHelpers,
  TellorCaller,
  RedemptionHelper,
  LiquidationHelper,
  Leverager,
  RewarderManager,
  CommunityIssuance,
  MultiTroveGetter,
} from "../../typechain-types";

type StablecoinOwnedContract =
  | CollateralConfig
  | PriceFeed
  | SortedTroves
  | TroveManager
  | RewarderManager
  | RedemptionHelper
  | LiquidationHelper
  | BorrowerOperations
  | StabilityPool
  | ActivePool
  | DefaultPool
  | CollSurplusPool
  | HintHelpers
  | Leverager
  | CommunityIssuance;

type StablecoinContract =
  | StablecoinOwnedContract
  | LUSDToken
  | GasPool
  | MultiTroveGetter
  | TellorCaller;

type ContractName =
  | "CollateralConfig"
  | "PriceFeed"
  | "SortedTroves"
  | "TroveManager"
  | "RewarderManager"
  | "RedemptionHelper"
  | "LiquidationHelper"
  | "BorrowerOperations"
  | "StabilityPool"
  | "ActivePool"
  | "DefaultPool"
  | "CollSurplusPool"
  | "HintHelpers"
  | "Leverager"
  | "CommunityIssuance"
  | "LUSDToken"
  | "GasPool"
  | "MultiTroveGetter"
  | "TellorCaller";

class ConfigurationParameters {
  public readonly etherscanURL: string;
  public readonly gasPriceWei: number;
  public readonly txConfirmations: number;
  public readonly collaterals: ReadonlyArray<Collateral>;
  public readonly externalAddresses: Record<string, string>;
  public readonly internalAddresses: Record<string, string>;
  public readonly contracts: ReadonlyArray<DeploymentContract>;

  constructor(
    etherscanURL: string,
    gasPriceWei: number,
    txConfirmations: number,
    collaterals: Array<Collateral>,
    externalAddresses: Record<string, string>,
    internalAddresses: Record<string, string>,
    contracts: ReadonlyArray<DeploymentContract>,
  ) {
    this.etherscanURL = etherscanURL;
    this.gasPriceWei = gasPriceWei;
    this.txConfirmations = txConfirmations;
    this.collaterals = collaterals;
    this.externalAddresses = externalAddresses;
    this.internalAddresses = internalAddresses;
    this.contracts = contracts;
  }
}

class Collateral {
  public readonly address: string;
  public readonly MCR: string;
  public readonly CCR: string;
  public readonly limit: string;
  public readonly chainlinkTimeoutSec: number;
  public readonly tellorTimeoutSec: number;
  public readonly chainlinkAggregatorAddress: string;
  public readonly tellorQueryID: string;
  public readonly maxPriceDeviation: number;

  constructor(
    address: string,
    MCR: string,
    CCR: string,
    limit: string,
    chainlinkTimeoutSec: number,
    tellorTimeoutSec: number,
    chainlinkAggregatorAddress: string,
    tellorQueryID: string,
    maxPriceDeviation: number,
  ) {
    this.address = address;
    this.MCR = MCR;
    this.CCR = CCR;
    this.limit = limit;
    this.chainlinkTimeoutSec = chainlinkTimeoutSec;
    this.tellorTimeoutSec = tellorTimeoutSec;
    this.chainlinkAggregatorAddress = chainlinkAggregatorAddress;
    this.tellorQueryID = tellorQueryID;
    this.maxPriceDeviation = maxPriceDeviation;
  }
}

class DeploymentContract {
  public readonly name: ContractName;
  public readonly ctorArguments: ReadonlyArray<any>;
  constructor(name: ContractName, ctorArguments: ReadonlyArray<any>) {
    this.name = name;
    this.ctorArguments = ctorArguments;
  }
}

interface Transaction {
  address: string;
  txHash: string;
  verification: string;
}

export {
  StablecoinContract,
  StablecoinOwnedContract,
  ConfigurationParameters,
  Collateral,
  DeploymentContract,
  ContractName,
  Transaction,
};

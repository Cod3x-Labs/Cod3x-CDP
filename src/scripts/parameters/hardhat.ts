import { ConfigurationParameters } from "../../utils/deploy/types";

const TELLOR_MASTER = "0x34Fae97547E990ef0E05e05286c51E4645bf1A85";
const GOVERNANCE_ADDRESS = "0x0000000000000000000000000000000000000000";
const GUARDIAN_ADDRESS = "0x0000000000000000000000000000000000000000";

export const configurationParameters: ConfigurationParameters =
  new ConfigurationParameters(
    "VERIFICATION_IS_SKIPPED",
    3_000_000_000,
    0,
    [
      {
        address: "0x0000000000000000000000000000000000000000",
        MCR: "1.1", // 1.1 ether = 110%
        CCR: "1.35", // 1.35 ether = 135%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // uint256 max
        chainlinkTimeoutSec: 14400, // 4 hours
        tellorTimeoutSec: 14400, // 4 hours
        chainlinkAggregatorAddress:
          "0xdC6720c996Fad27256c7fd6E0a271e2A4687eF18", //Chronicle labs
        tellorQueryID:
          "0x6908dd654640ba7c223a7bfb615a6b6238b839f31e3cdcc8804483a620439912",
        maxPriceDeviation: "500000000000000000" // 50%
      },
    ],
    {
      OATH: "0x0000000000000000000000000000000000000000",
      SWAPPER: "0x0000000000000000000000000000000000000000",
      VELO_ROUTER: "0x0000000000000000000000000000000000000000",
      BALANCER_VAULT: "0x0000000000000000000000000000000000000000",
      UNI_V3_ROUTER: "0x0000000000000000000000000000000000000000",
    },
    {
      DEPLOYER: "0x0000000000000000000000000000000000000000",
      GOVERNANCE: GOVERNANCE_ADDRESS,
      TREASURY: "0x0000000000000000000000000000000000000000",
      LUSD_TOKEN: "0x0000000000000000000000000000000000000000",
    },
    [
      {
        name: "CollateralConfig",
        ctorArguments: [],
      },
      {
        name: "PriceFeed",
        ctorArguments: [],
      },
      {
        name: "SortedTroves",
        ctorArguments: [],
      },
      {
        name: "TroveManager",
        ctorArguments: [],
      },
      {
        name: "RewarderManager",
        ctorArguments: [],
      },
      {
        name: "RedemptionHelper",
        ctorArguments: [],
      },
      {
        name: "LiquidationHelper",
        ctorArguments: [],
      },
      {
        name: "BorrowerOperations",
        ctorArguments: [],
      },
      {
        name: "StabilityPool",
        ctorArguments: [],
      },
      {
        name: "ActivePool",
        ctorArguments: [],
      },
      {
        name: "DefaultPool",
        ctorArguments: [],
      },
      {
        name: "CollSurplusPool",
        ctorArguments: [],
      },
      {
        name: "HintHelpers",
        ctorArguments: [],
      },
      {
        name: "Leverager",
        ctorArguments: [],
      },
      {
        name: "CommunityIssuance",
        ctorArguments: [],
      },
      {
        name: "LUSDToken",
        ctorArguments: [
          "SET_TROVEMANAGER_ADDRESS",
          "SET_STABILITYPOOL_ADDRESS",
          "SET_BORROWEROPERATONS_ADDRESS",
          GOVERNANCE_ADDRESS,
          GUARDIAN_ADDRESS,
        ],
      },
      {
        name: "MultiTroveGetter",
        ctorArguments: [
          "SET_COLLATERALCONFIG_ADDRESS",
          "SET_TROVEMANAGER_ADDRESS",
          "SET_SORTEDTROVES_ADDRESS",
        ],
      },
      {
        name: "GasPool",
        ctorArguments: [],
      },
      {
        name: "TellorCaller",
        ctorArguments: [TELLOR_MASTER],
      },
    ],
  );

import { ConfigurationParameters } from "../../utils/deploy/types";

const TELLOR_MASTER = "0x0000000000000000000000000000000000000000";
const GOVERNANCE_ADDRESS = "0xB26cd6633dB6B0C9AE919049c1437271Ae496D15";
const GUARDIAN_ADDRESS = "0xB26cd6633dB6B0C9AE919049c1437271Ae496D15";

export const configurationParameters: ConfigurationParameters =
  new ConfigurationParameters(
    "https://modescan.io/address",
    0.0000003,
    1,
    [
      {
        address: "0x85be9bc0D401b97179A155398F6FeaE70918806d", // USDC
        MCR: "1.05", // 1.05 ether = 105%
        CCR: "1.15", // 1.15 ether = 115%
        limit:
          "1000000000000000000000", // $1000
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x8a771f81d82c6eA9eeC8F0499286ceDb6B72eF30", // Redstone adapter
        tellorQueryID:
          "0x8ee44cd434ed5b0e007eee581fbe0855336f3f84484e8d9989a620a4a49aa0f7",
        maxPriceDeviation: "50000000000000000", // 5%
      },
      {
        address: "0x3e6e390322742e4931E77f32c390D98fa96573eD", // USDT
        MCR: "1.05", // 1.05 ether = 105%
        CCR: "1.15", // 1.15 ether = 115%
        limit:
          "1000000000000000000000", // $1000
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0xAD2FF91c82D6dA6Dc192116086deE6d1f9e5431B", // Redstone adapter
        tellorQueryID:
          "0x68a37787e65e85768d4aa6e385fb15760d46df0f67a18ec032d8fd5848aca264",
        maxPriceDeviation: "50000000000000000", // 5%
      },
    ],
    {
      OATH: "0x95177295A394f2b9B04545FFf58f4aF0673E839d",
      SWAPPER: "0xF86F3Cba7034d0072725b480b09BC84f3851E119",
    },
    {
      DEPLOYER: "0xe00691e65Cd4400c84a174a4C56f20bA43dffD89",
      GOVERNANCE: GOVERNANCE_ADDRESS,
      GUARDIAN: GUARDIAN_ADDRESS,
      TREASURY: "0x788F382d835Cb00851b883DAD7f30798AE480622",
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
        name: "BorrowerHelper",
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
          "0x7759103B20CcB133799c12e3B9203B27465b2738",
          "0x1eFcDA945bbb19E250C58acfEAc237d43eFDca39",
          "0x9a15e8D2c0457a9a46b50B1A155F65948510bf6D",
          GOVERNANCE_ADDRESS,
          GUARDIAN_ADDRESS,
        ],
      },
      {
        name: "MultiTroveGetter",
        ctorArguments: [
          "0x4AEd341207B6DBE7e18045eD5571EdefD58c8bc3",
          "0x7759103B20CcB133799c12e3B9203B27465b2738",
          "0x102341c08F3c0932630f39F2eAae0eAe76D7F928",
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

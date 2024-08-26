import { ConfigurationParameters } from "../../utils/deploy/types";

const TELLOR_MASTER = "0x0000000000000000000000000000000000000000";
const GOVERNANCE_ADDRESS = "0x538E46Ad781E9B8ce3aAE4e1BDa68250F72c16d1";
const GUARDIAN_ADDRESS = "0x64dfD485B4Da1af3F2cE1C86Cfc3E7bD9093B468";

export const configurationParameters: ConfigurationParameters =
  new ConfigurationParameters(
    "https://modescan.io/address",
    0.0000003,
    5,
    [
      {
        address: "0x3117c7854d11cB0216c82B81934CAaFe0722BB44", // WETH vault
        MCR: "1.08", // 1.08 ether = 108%
        CCR: "1.2", // 1.20 ether = 120%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 32400, // 9 hours
        tellorTimeoutSec: 32400, // 9 hours
        chainlinkAggregatorAddress:
          "0x0c52eACEBe1E458943a7A458fdd6d436D805B34F", // Redstone adapter
        tellorQueryID:
          "0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0xF7BC8B00a065943dC8D7B63E9632D7F987731C05", // MODE vault
        MCR: "1.2", // 1.20 ether = 120%
        CCR: "1.65", // 1.65 ether = 165%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x8dd2D85C7c28F43F965AE4d9545189C7D022ED0e", // Redstone adapter
        tellorQueryID:
          "0xc20aa4918a4df6b79e3048755a98597d65451dd1bc2dcb85f554456bcfafea20",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0x882fD369341FC435ad5E54e91d1ebC23b1Fc6d4C", // USDC vault
        MCR: "1.05", // 1.05 ether = 105%
        CCR: "1.15", // 1.15 ether = 115%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 32400, // 9 hours
        tellorTimeoutSec: 32400, // 9 hours
        chainlinkAggregatorAddress:
          "0x8a771f81d82c6eA9eeC8F0499286ceDb6B72eF30", // Redstone adapter
        tellorQueryID:
          "0x8ee44cd434ed5b0e007eee581fbe0855336f3f84484e8d9989a620a4a49aa0f7",
        maxPriceDeviation: "50000000000000000", // 5%
      },
      {
        address: "0xc9cfB5221eE50098BD8882727522301A62C7b021", // USDT vault
        MCR: "1.05", // 1.05 ether = 105%
        CCR: "1.15", // 1.15 ether = 115%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 32400, // 9 hours
        tellorTimeoutSec: 32400, // 9 hours
        chainlinkAggregatorAddress:
          "0xAD2FF91c82D6dA6Dc192116086deE6d1f9e5431B", // Redstone adapter
        tellorQueryID:
          "0x68a37787e65e85768d4aa6e385fb15760d46df0f67a18ec032d8fd5848aca264",
        maxPriceDeviation: "50000000000000000", // 5%
      },
      {
        address: "0xd9139c2dba16513eAd360658496c9c8223158Cd5", // ezETH vault
        MCR: "1.1", // 1.1 ether = 110%
        CCR: "1.4", // 1.40 ether = 140%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 32400, // 9 hours
        tellorTimeoutSec: 32400, // 9 hours
        chainlinkAggregatorAddress:
          "0x48FD15267E76E3E3e5a6Ffd5D431602d86a6a3f5", // Redstone adapter
        tellorQueryID:
          "0x4bdb348572b7adb1348eb018c2206bc9813fb18ff75e00d3feb2d4b7f724d605",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      /*{
        address: "0xcd7362BAC88cBB52698ce849699a5D543Bb7236e", // M-BTC vault
        MCR: "1.1", // 1.1 ether = 110%
        CCR: "1.35", // 1.35 ether = 135%
        limit:
          "300000000000000000000000", // $300,000
        chainlinkTimeoutSec: 32400, // 9 hours
        tellorTimeoutSec: 32400, // 9 hours
        chainlinkAggregatorAddress:
          "", // Redstone adapter
        tellorQueryID:
          "0x9feed1b0d5bde21d77d651b528d35c71ce805ec0fb90796a31a3111caed7860f",
        maxPriceDeviation: "500000000000000000", // 50%
      },*/
    ],
    {
      OATH: "0x3B6eA0fA8A487c90007ce120a83920fd52b06f6D", // oICL
      SWAPPER: "0x7a8bCF0E414bEd532DB7908B9d315A2f2dd4BB5C",
    },
    {
      DEPLOYER: "0xe00691e65Cd4400c84a174a4C56f20bA43dffD89",
      GOVERNANCE: GOVERNANCE_ADDRESS,
      GUARDIAN: GUARDIAN_ADDRESS,
      TREASURY: "0x788F382d835Cb00851b883DAD7f30798AE480622",
      LUSD_TOKEN: "0xA70266C8F8Cf33647dcFEE763961aFf418D9E1E4",
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
          "", // TroveManager
          "", // StabilityPool
          "", // BorrowerOperations
          GOVERNANCE_ADDRESS,
          GUARDIAN_ADDRESS,
        ],
      },
      {
        name: "MultiTroveGetter",
        ctorArguments: [
          "0xBc7A614955388DFfb9d5e1ce27D32Cd186eEA2ec", // CollateralConfig
          "0x829746b34F624fdB03171AA4cF4D2675B0F2A2e6", // TroveManager
          "0x349a53D38C7fe6F688165E8f20703a386D505B4C", // SortedTroves
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

import { ConfigurationParameters } from "../../utils/deploy/types";

const TELLOR_MASTER = "0x0000000000000000000000000000000000000000";
const GOVERNANCE_ADDRESS = "0x1c8787c8E7a1C35a76cD7260560EA4EAA62b0ded";
const GUARDIAN_ADDRESS = "0x829bEcCBF4c8b2d51e0F2b3eb60d426D482A6287";

export const configurationParameters: ConfigurationParameters =
  new ConfigurationParameters(
    "https://scrollscan.com/address",
    0.0000003, // not used
    20,
    [
      {
        address: "0x295c6074F090f85819cbC911266522e43A8e0f4A", // WETH vault
        MCR: "1.08", // 1.08 ether = 108%
        CCR: "1.25", // 1.25 ether = 125%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x79683D2ccefd7307f1649F8F8A987D232dc99A72", // Redstone adapter
        tellorQueryID:
          "0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0x84B6950E1aaAE25847b7f92608832A572Bc4a90f", // USDC vault
        MCR: "1.05", // 1.05 ether = 105%
        CCR: "1.1", // 1.1 ether = 110%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x874aE50644E56C900CBe6f3C8dabBAA991176c80", // Redstone adapter
        tellorQueryID:
          "0x8ee44cd434ed5b0e007eee581fbe0855336f3f84484e8d9989a620a4a49aa0f7",
        maxPriceDeviation: "50000000000000000", // 5%
      },
      {
        address: "0x4Cd23F2C694F991029B85af5575D0B5E70e4A3F1", // wstETH vault
        MCR: "1.12", // 1.12 ether = 112%
        CCR: "1.3", // 1.30 ether = 130%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x89A42aAc15339479e0Bba6e3B32d40CAeFAcCd98", // Redstone adapter
        tellorQueryID:
          "0x1962cde2f19178fe2bb2229e78a6d386e6406979edc7b9a1966d89d83b3ebf2e",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0xea4D4B49F181EfE74334a440605C7316454c7045", // weETH vault
        MCR: "1.12", // 1.12 ether = 112%
        CCR: "1.35", // 1.35 ether = 135%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0xD039577917A164F8Fd1Ee54c6Fb90b781eA04716", // Redstone adapter
        tellorQueryID:
          "0x359df975c1135cfa5aa6998088913bcfd900493bf7bcd2466f81f9131a174544",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0x199f19926D8b499b6EadCB14F23f39200d785acC", // pufETH vault
        MCR: "1.15", // 1.15 ether = 115%
        CCR: "1.4", // 1.40 ether = 140%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x74Ad03C9952C6Be7D1deAD0cdF0025d65b5e87B5", // Redstone adapter
        tellorQueryID:
          "0x5f2535530a478ef869e204491d9050768af6c213b082270cf3701bdb31e2b03a",
        maxPriceDeviation: "500000000000000000", // 50%
      },
      {
        address: "0xAA38A75bfF218AdEEbcBA75B03370fC6aABCB98b", // STONE vault
        MCR: "1.12", // 1.12 ether = 112%
        CCR: "1.35", // 1.35 ether = 135%
        limit:
          "115792089237316195423570985008687907853269984665640564039457584007913129639935", // max uint
        chainlinkTimeoutSec: 97200, // 27 hours
        tellorTimeoutSec: 97200, // 27 hours
        chainlinkAggregatorAddress:
          "0x8216C3e36792050C033e56CE9F338e1C973d16A2", // Redstone adapter
        tellorQueryID:
          "0x1a63c3b95022ce6e0112c2d9b27e699b5493f890bb2734e5148402eeadbae5e6",
        maxPriceDeviation: "500000000000000000", // 50%
      },
    ],
    {
      OATH: "0xf270bFe3F97655Fff1D89aFf50a8E1dc381941b5", // oLORE
      SWAPPER: "0x13155Ea5D9b3471ad31A47Bc82672f0538FA142E",
    },
    {
      DEPLOYER: "0xe00691e65Cd4400c84a174a4C56f20bA43dffD89",
      GOVERNANCE: GOVERNANCE_ADDRESS,
      GUARDIAN: GUARDIAN_ADDRESS,
      TREASURY: "0x159cC26BcAB2851835e963D0C24E1956b2279Ca9",
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
          "0x229D05957A052b836DBD7D528F39ef438f9135Fb", // TroveManager
          "0x81df91f066d935EF3655eE7ffBAc036A6fDF6226", // StabilityPool
          "0x3DBcD766770998D583996A6cC65D530bB415CeA5", // BorrowerOperations
          GOVERNANCE_ADDRESS,
          GUARDIAN_ADDRESS,
        ],
      },
      {
        name: "MultiTroveGetter",
        ctorArguments: [
          "0xEaed3db8bbbe135EeaEb7487D2F30CDeCE01DAdf", // CollateralConfig
          "0x229D05957A052b836DBD7D528F39ef438f9135Fb", // TroveManager
          "0x1eFcDA945bbb19E250C58acfEAc237d43eFDca39", // SortedTroves
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

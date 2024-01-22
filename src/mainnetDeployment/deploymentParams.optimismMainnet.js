const externalAddrs  = {
  TELLOR_MASTER:"0x8cFc184c877154a8F9ffE0fe75649dbe5e2DBEbf",
  OATH: "0x00e1724885473B63bCE08a9f0a52F35b0979e35A",
  STAKING_TOKEN: "0xD13D81aF624956327A24d0275CBe54b0eE0E9070",
  SWAPPER: "0x1FFa0AF1Fa5bdfca491a21BD4Eab55304c623ab8",
  VELO_ROUTER: "0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858",
  BALANCER_VAULT: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
  UNI_V3_ROUTER: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
}

const collaterals = [
  {
    address: "0x68f180fcCe6836688e9084f035309E29Bf0A2095", // WBTC
    MCR: "1.1", // 1.1 ether = 110%
    CCR: "1.35", // 1.35 ether = 135%
    limit: "115792089237316195423570985008687907853269984665640564039457584007913129639935", // uint256 max
    chainlinkTimeout: 14400, // 4 hours
    tellorTimeout: 14400, // 4 hours
    chainlinkAggregatorAddress: "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593",
    tellorQueryID: "0xa6f013ee236804827b77696d350e9f0ac3e879328f2a3021d473a0b778ad78ac",
    reaperVaultAddress: "0xbb341D8249c1C747708D4e6F7Cd967A2479CAD75"
  },
  {
    address: "0x4200000000000000000000000000000000000006", // WETH
    MCR: "1.08", // 1.08 ether = 108%
    CCR: "1.2", // 1.2 ether = 120%
    limit: "115792089237316195423570985008687907853269984665640564039457584007913129639935", // uint256 max
    chainlinkTimeout: 14400, // 4 hours
    tellorTimeout: 14400, // 4 hours
    chainlinkAggregatorAddress: "0x13e3Ee699D1909E989722E753853AE30b17e08c5",
    tellorQueryID: "0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992",
    reaperVaultAddress: "0x7c09733834873b1FDB8A70c19eE1A514023f74f9"
  },
  {
    address: "0x1f32b1c2345538c0c6f582fcb022739c4a194ebb", // wstETH
    MCR: "1.1", // 1.1 ether = 110%
    CCR: "1.35", // 1.35 ether = 135%
    limit: "2000000000000000000000000", // $2,000,000
    chainlinkTimeout: 97200, // 27 hours
    tellorTimeout: 14400, // 4 hours
    chainlinkAggregatorAddress: "0x698B585CbC4407e2D54aa898B2600B53C68958f7",
    tellorQueryID: "0x1962cde2f19178fe2bb2229e78a6d386e6406979edc7b9a1966d89d83b3ebf2e",
    reaperVaultAddress: "0xA70266C8F8Cf33647dcFEE763961aFf418D9E1E4"
  },
/*   {
    address: "0x4200000000000000000000000000000000000042", // OP
    MCR: "1.15", // 1.15 ether = 115%
    CCR: "1.5", // 1.5 ether = 150%
    limit: "115792089237316195423570985008687907853269984665640564039457584007913129639935", // uint256 max
    timeout: 14400, // 4 hours
    chainlinkAggregatorAddress: "0x0D276FC14719f9292D5C1eA2198673d1f4269246",
    tellorQueryID: "0xafc6a3f6c18df31f1078cf038745b48e55623330715d90efe3dc7935efd44938",
    reaperVaultAddress: "0x6938b5b43b281bF24202437b86bbd2866a79cF6C"
  } */
];

const liquityAddrs = {
  DEPLOYER: "0xe00691e65Cd4400c84a174a4C56f20bA43dffD89", // Mainnet REAL deployment address
  GOVERNANCE: "0xf1a717766c1b2Ed3f63b602E6482dD699ce1C79C", // to be passed to LUSDToken as governance address
  GUARDIAN: "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9", // to be passed to LUSDToken as guardian address
  TREASURY: "0xf1a717766c1b2Ed3f63b602E6482dD699ce1C79C", // to be passed to ActivePool as treasury address
  LUSD_TOKEN: "0xc5b001DC33727F8F26880B184090D3E252470D45"
}

const OUTPUT_FILE = './mainnetDeployment/optimismMainnetV2_1DeploymentOutput.json'

const delay = ms => new Promise(res => setTimeout(res, ms));
const waitFunction = async () => {
  return delay(90000) // wait 90s
}

const GAS_PRICE = 225000000
const TX_CONFIRMATIONS = 3 // for mainnet

const ETHERSCAN_BASE_URL = 'https://optimistic.etherscan.io/address'

module.exports = {
  externalAddrs,
  collaterals,
  liquityAddrs,
  OUTPUT_FILE,
  waitFunction,
  GAS_PRICE,
  TX_CONFIRMATIONS,
  ETHERSCAN_BASE_URL,
};

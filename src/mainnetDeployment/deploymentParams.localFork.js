const externalAddrs  = {
  TELLOR_MASTER:"0xD9157453E2668B2fc45b7A803D3FEF3642430cC0",
  OATH: "0x39FdE572a18448F8139b7788099F0a0740f51205",
  STAKING_TOKEN: "0x99184713bad36bdcbC31453670FBB0D2eC3Cfcc4",
  SWAPPER: "0x1FFa0AF1Fa5bdfca491a21BD4Eab55304c623ab8",
}

const collaterals = [
  {
    address: "0x68f180fcCe6836688e9084f035309E29Bf0A2095", // WBTC
    MCR: "1.2", // 1.2 ether = 120%
    CCR: "1.5", // 1.5 ether = 150%
    limit: "115792089237316195423570985008687907853269984665640564039457584007913129639935", // uint256 max
    chainlinkTimeout: 14400, // 4 hours
    tellorTimeout: 14400, // 4 hours
    chainlinkAggregatorAddress: "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593",
    tellorQueryID: "0xa6f013ee236804827b77696d350e9f0ac3e879328f2a3021d473a0b778ad78ac",
    reaperVaultAddress: "0x3aA179c2F70D1D022afBc1f779177b8739Cc45D1"
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
    reaperVaultAddress: "0x099913e22a0dB0E3e6D8A67506e46DC168fa0174"
  }
];

const liquityAddrs = {
  DEPLOYER: "0x31c57298578f7508B5982062cfEc5ec8BD346247", // Mainnet REAL deployment address
  GOVERNANCE: "0x9BC776dBb134Ef9D7014dB1823Cd755Ac5015203", // to be passed to LUSDToken as governance address
  GUARDIAN: "0xb0C9D5851deF8A2Aac4A23031CA2610f8C3483F9", // to be passed to LUSDToken as guardian address
  TREASURY: "0xeb9C9b785aA7818B2EBC8f9842926c4B9f707e4B", // to be passed to ActivePool as treasury address
}

const OUTPUT_FILE = './mainnetDeployment/localForkDeploymentOutput.json'

const waitFunction = async () => {
  // Fast forward time 1000s (local mainnet fork only)
  ethers.provider.send("evm_increaseTime", [1000])
  ethers.provider.send("evm_mine") 
}

const GAS_PRICE = 875175000
const TX_CONFIRMATIONS = 1 // for local fork test

module.exports = {
  externalAddrs,
  collaterals,
  liquityAddrs,
  OUTPUT_FILE,
  waitFunction,
  GAS_PRICE,
  TX_CONFIRMATIONS,
};

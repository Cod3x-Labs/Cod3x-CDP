import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-truffle5";
import "dotenv-defaults/config";
require("@nomicfoundation/hardhat-foundry");

const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: { optimizer: { enabled: true }, viaIR: true, evmVersion: "paris" },
      },
      {
        version: "0.4.23",
      },
    ],
  },
  networks: {
    local: {
      url: "http://127.0.0.1:8545",
    },
    mode: {
      url: "https://mainnet.mode.network",
      chainId: 34443,
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: {
      mode: "mode",
    },
    customChains: [
      {
        network: "mode",
        chainId: 34443,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/34443/etherscan",
          browserURL: "https://modescan.io",
        },
      },
    ],
  },
};

export default config;

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-truffle5";
import "dotenv-defaults/config";
require("@nomicfoundation/hardhat-foundry");

const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const SCROLLSCAN_KEY = process.env.SCROLLSCAN_API_KEY;

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
    scroll: {
      url: "https://scroll.drpc.org",
      chainId: 534352,
      accounts: [`0x${PRIVATE_KEY}`],
    },
  },
  etherscan: {
    apiKey: {
      mode: "mode",
      scroll: SCROLLSCAN_KEY as string,
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
      {
        network: "scroll",
        chainId: 534352,
        urls: {
          apiURL: "https://api.scrollscan.com/api",
          browserURL: "https://scrollscan.com",
        },
      },
    ],
  },
};

export default config;

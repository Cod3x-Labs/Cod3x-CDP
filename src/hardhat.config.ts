import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-truffle5";
import "dotenv-defaults/config";
require("@nomicfoundation/hardhat-foundry");

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
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;

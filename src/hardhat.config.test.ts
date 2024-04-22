import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@nomiclabs/hardhat-truffle5";
import "dotenv-defaults/config";
import { accountsList } from "./utils/accountsList.js";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: { optimizer: { enabled: true }, viaIR: true },
      },
      {
        version: "0.4.23",
      },
    ],
  },
  networks: {
    hardhat: {
      accounts: accountsList,
      initialBaseFeePerGas: 0, //this setting is needed for some of tests to work
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;

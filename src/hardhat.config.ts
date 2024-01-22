import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-truffle5";
import "dotenv-defaults/config";

import { accountsList } from "./hardhatAccountsList2k.js";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{ version: "0.8.23" }, { version: "0.6.11" }, { version: "0.4.23" }]
  },
  networks: {
    hardhat: {
      accounts: accountsList,
      initialBaseFeePerGas: 0, //this setting is needed for some of tests to work
    },
  }
};

export default config;

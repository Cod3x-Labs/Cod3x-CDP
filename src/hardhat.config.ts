import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv-defaults/config";

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{ version: "0.8.23" }, { version: "0.6.11" }, { version: "0.4.23" }]
  },
  networks: {
    hardhat: {
      forking: {
        enabled: false,
        url: ``
      }
    }
  }
};

export default config;

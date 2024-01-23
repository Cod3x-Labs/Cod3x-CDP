require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-truffle5");
require("dotenv-defaults/config");

const accounts = require("./utils/hardhatAccountsList2k.js");
const accountsList = accounts.accountsList;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.4.23",
      },
      {
        version: "0.8.23",
        settings: {
          optimizer: {
            enabled: true,
          },
          viaIR: true,
        },
      },
    ],
  },
  networks: {
    hardhat: {
      accounts: accountsList,
      initialBaseFeePerGas: 0,
    },
  },
};

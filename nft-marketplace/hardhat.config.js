require("@nomiclabs/hardhat-waffle")
require('dotenv').config();

const { MUMBAI_API_URL, POLYGON_API_URL, PRIVATE_KEY } = process.env;

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      chainId: 1337
    },
    mumbai: {
      url: MUMBAI_API_URL,
      accounts: [PRIVATE_KEY]
    },
    mainnet: {
      url: POLYGON_API_URL,
      accounts: [PRIVATE_KEY]
    }
  },
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
}
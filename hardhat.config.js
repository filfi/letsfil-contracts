require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("dotenv/config"); 
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("./tasks");


const PRIVATE_KEY = process.env.PRIVATE_KEY
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.17",
    viaIR: true,
    settings: {
      optimizer: {
          enabled: true,
          runs: 200,
          details: {
            yul: false
          }
      }
    }
  },
  defaultNetwork: "test2k",
  // defaultNetwork: "hyperspace",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    hyperspace: {
        chainId: 3141,
        url: "https://api.hyperspace.node.glif.io/rpc/v1",
        accounts: [PRIVATE_KEY],
    },
    test2k: {
      url: "http://10.100.244.100:41234/rpc/v1",
      accounts: [PRIVATE_KEY]
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "deploy",
    deployments: "deployments",
  },
  gasReporter: {
    // enabled: true
  }
};

require('@nomicfoundation/hardhat-toolbox')
require('dotenv').config()

const deployerKey = process.env.DEPLOYER_PRIVATE_KEY
const accounts = deployerKey ? [deployerKey] : []

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: 'shanghai',
      // viaIR: true, // turn on only if the compiler reports "stack too deep"
    },
  },
  networks: {
    bscTestnet: {
      url:
        process.env.BSC_TESTNET_RPC_URL ||
        'https://data-seed-prebsc-1-s1.bnbchain.org:8545',
      chainId: 97,
      accounts,
    },
    bsc: {
      url: process.env.BSC_RPC_URL || 'https://bsc-dataseed.bnbchain.org',
      chainId: 56,
      accounts,
    },
  },
  etherscan: {
    // BscScan verification uses an Etherscan API key
    apiKey: process.env.ETHERSCAN_API_KEY || '',
  },
}

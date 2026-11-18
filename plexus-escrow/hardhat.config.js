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
      // Fixed price: the public RPCs sometimes suggest a tip below the 0.1 gwei network minimum
      // ("gas tip cap ... minimum needed 100000000"). 1 gwei costs fractions of a cent on testnet.
      gasPrice: Math.round(Number(process.env.BSC_TESTNET_GAS_PRICE_GWEI || 1) * 1e9),
    },
    bsc: {
      url: process.env.BSC_RPC_URL || 'https://bsc-dataseed.bnbchain.org',
      chainId: 56,
      accounts,
    },
  },
  etherscan: {
    // BscScan verification uses an Etherscan API key. A FREE key does not cover BSC testnet (chain 97):
    // scripts/lib/verifyV2.js checks this and falls back to Sourcify + a manual BscScan bundle.
    apiKey: process.env.ETHERSCAN_API_KEY || '',
  },
  // Free, no key needed; supports BSC mainnet and testnet
  sourcify: { enabled: true },
}

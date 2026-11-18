// BSC testnet requires a priority fee of at least 0.1 gwei, but public RPCs sometimes suggest less
// ("gas tip cap 62500000, minimum needed 100000000"). hardhat.config.js fixes the price for Hardhat's
// own accounts; this does the same for plain ethers Wallets (e.g. the throwaway test wallets), which
// otherwise ask the node for fee suggestions on every transaction.
const { ethers } = require("hardhat");

function useFixedGasPrice(provider, gwei = process.env.BSC_TESTNET_GAS_PRICE_GWEI || 1) {
  const gasPrice = BigInt(Math.round(Number(gwei) * 1e9));
  // legacy (type 0) transactions: gasPrice only, no EIP-1559 fields
  provider.getFeeData = async () => new ethers.FeeData(gasPrice, null, null);
  return gasPrice;
}

module.exports = { useFixedGasPrice };

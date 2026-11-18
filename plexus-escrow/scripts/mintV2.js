// Mint test USDT (MockUSDT) to any wallet. Testnet only: MockUSDT.mint is open to everyone.
//   default: 10,000 USDT to the deployer wallet
//   custom : MINT_TO=0x... MINT_AMOUNT=500 npx hardhat run scripts/mintV2.js --network bscTestnet
//   PowerShell: $env:MINT_TO="0x..."; $env:MINT_AMOUNT="500"; npm run mint:testnet
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

async function main() {
  const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
  if (!fs.existsSync(file)) throw new Error(`No deployment found: ${file}`);
  const info = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!info.mockDeployed) throw new Error("This deployment uses a real token; nothing to mint.");

  const [deployer] = await ethers.getSigners();
  const to = process.env.MINT_TO || deployer.address;
  if (!ethers.isAddress(to)) throw new Error(`MINT_TO is not a valid address: ${to}`);
  const amount = process.env.MINT_AMOUNT || "10000";

  const token = await ethers.getContractAt("MockUSDT", info.token);
  const tx = await token.mint(to, ethers.parseEther(amount));
  await tx.wait();
  const balance = await token.balanceOf(to);
  console.log(`Minted ${amount} USDT to ${to}`);
  console.log(`New balance: ${ethers.formatEther(balance)} USDT`);
  console.log(`Token: ${info.token}  (symbol USDT, 18 decimals)`);
  if (network.name === "bscTestnet") console.log(`https://testnet.bscscan.com/tx/${tx.hash}`);
}

main().catch((e) => { console.error(e.shortMessage || e.message); process.exitCode = 1; });

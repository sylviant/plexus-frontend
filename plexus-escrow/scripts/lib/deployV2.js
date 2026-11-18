const { ethers, network } = require("hardhat");

const FEE_BPS = 200; // 2% commission
const REFERRER_BPS = 3000; // 30% of commission
const CASHBACK_BPS = 2000; // 20% of commission

/**
 * Deploys MockUSDT (unless TOKEN_ADDRESS is set) and PlexusEscrowV2.
 * On the in-process hardhat network, missing roles fall back to local signers.
 */
async function deployAll() {
  const [deployer, s1, s2, s3] = await ethers.getSigners();
  const local = network.name === "hardhat" || network.name === "localhost";
  const env = process.env;

  if (network.name === "bsc") throw new Error("Mainnet deploy is intentionally not supported by this script.");
  if (!deployer) throw new Error("No deployer: set DEPLOYER_PRIVATE_KEY in .env");

  // Local chains always use the local test accounts, never the real addresses in .env
  // (those exist only on the public network, and the local scripts must hold their keys).
  const owner = local ? deployer.address : env.OWNER_MULTISIG;
  const operator = local ? s1.address : env.OPERATOR_ADDRESS;
  const treasury = local ? s2.address : env.TREASURY_ADDRESS;
  for (const [k, v] of Object.entries({ OWNER_MULTISIG: owner, OPERATOR_ADDRESS: operator, TREASURY_ADDRESS: treasury })) {
    if (!ethers.isAddress(v)) throw new Error(`${k} is missing or invalid in .env`);
  }
  const minWithdrawal = ethers.parseEther(env.MIN_REWARD_WITHDRAWAL_USDT || "5");

  const chainId = Number((await ethers.provider.getNetwork()).chainId);
  console.log(`Network:   ${network.name} (chainId ${chainId})`);
  console.log(`Deployer:  ${deployer.address}`);
  console.log(`Balance:   ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} native`);
  console.log(`Owner:     ${owner}\nOperator:  ${operator}\nTreasury:  ${treasury}`);

  let tokenAddress = local ? undefined : env.TOKEN_ADDRESS; // a testnet token address means nothing locally
  let mockDeployed = false;
  if (!tokenAddress) {
    const Token = await ethers.getContractFactory("MockUSDT");
    const token = await Token.deploy();
    await token.waitForDeployment();
    tokenAddress = await token.getAddress();
    mockDeployed = true;
    console.log(`MockUSDT deployed: ${tokenAddress}`);
  } else {
    console.log(`Using existing token: ${tokenAddress}`);
  }

  const Escrow = await ethers.getContractFactory("PlexusEscrowV2");
  const escrow = await Escrow.deploy(tokenAddress, owner, operator, treasury, FEE_BPS, REFERRER_BPS, CASHBACK_BPS, minWithdrawal);
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  console.log(`PlexusEscrowV2 deployed: ${escrowAddress}`);

  return {
    network: network.name,
    chainId,
    deployer: deployer.address,
    owner, operator, treasury,
    token: tokenAddress, mockDeployed,
    escrow: escrowAddress,
    feeBps: FEE_BPS, referrerBps: REFERRER_BPS, cashbackBps: CASHBACK_BPS,
    minWithdrawal: minWithdrawal.toString(),
    deployTx: escrow.deploymentTransaction().hash,
    deployedAt: new Date().toISOString(),
    _localSigners: { s1, s2, s3 },
  };
}

module.exports = { deployAll };

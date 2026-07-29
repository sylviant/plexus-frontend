const { ethers } = require("hardhat");

async function main() {
  console.log("Déploiement de PlexusEscrow sur BSC Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Wallet utilisé :", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Solde :", ethers.formatEther(balance), "tBNB");

  const Escrow = await ethers.getContractFactory("PlexusEscrow");
  const escrow = await Escrow.deploy(200); // 2% commission
  await escrow.waitForDeployment();

  const adresse = await escrow.getAddress();
  console.log("✅ Contrat déployé à l'adresse :", adresse);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
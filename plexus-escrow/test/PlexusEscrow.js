const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PlexusEscrow", function () {

  let escrow, owner, acheteur, vendeur;

  beforeEach(async function () {
    [owner, acheteur, vendeur] = await ethers.getSigners();
    const Escrow = await ethers.getContractFactory("PlexusEscrow");
    escrow = await Escrow.deploy(200); // 2% de commission
    await escrow.waitForDeployment();
  });

  it("Crée une commande et verrouille les fonds", async function () {
    const montant = ethers.parseEther("1.0");
    await escrow.connect(acheteur).creerCommande(vendeur.address, 7, {
      value: montant
    });
    const cmd = await escrow.getCommande(0);
    expect(cmd[2]).to.equal(montant); // montant correct
    expect(cmd[3]).to.equal(0);       // statut EnAttente
  });

  it("Confirme la livraison et paie le vendeur", async function () {
    const montant = ethers.parseEther("1.0");
    await escrow.connect(acheteur).creerCommande(vendeur.address, 7, {
      value: montant
    });

    const balanceAvant = await ethers.provider.getBalance(vendeur.address);
    await escrow.connect(acheteur).confirmerLivraison(0);
    const balanceApres = await ethers.provider.getBalance(vendeur.address);

    // Vendeur reçoit 98% (2% commission PLEXUS)
    expect(balanceApres - balanceAvant).to.equal(ethers.parseEther("0.98"));
  });

  it("Rembourse l'acheteur si délai dépassé", async function () {
    const montant = ethers.parseEther("1.0");
    await escrow.connect(acheteur).creerCommande(vendeur.address, 0, {
      value: montant
    });

    await escrow.connect(acheteur).demanderRemboursement(0);
    const cmd = await escrow.getCommande(0);
    expect(cmd[3]).to.equal(2); // statut Rembourse
  });

  it("Gère un litige", async function () {
    const montant = ethers.parseEther("1.0");
    await escrow.connect(acheteur).creerCommande(vendeur.address, 7, {
      value: montant
    });

    await escrow.connect(acheteur).ouvrirLitige(0);
    const cmd = await escrow.getCommande(0);
    expect(cmd[3]).to.equal(3); // statut Litige
  });

});
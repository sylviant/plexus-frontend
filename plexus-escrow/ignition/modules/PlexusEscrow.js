const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("PlexusEscrowModule", (m) => {
  const frais = m.getParameter("platformFee", 200); // 2% par défaut

  const escrow = m.contract("PlexusEscrow", [frais]);

  return { escrow };
});